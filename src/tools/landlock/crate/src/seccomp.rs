// SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
// SPDX-License-Identifier: MPL-2.0

//! Filtro seccomp-BPF: bloquea syscalls de cambio de modo/propietario/xattr
//! que Landlock NO cubre (gap: chmod/chown/setxattr).
//!
//! Layout del filtro (corregido respecto a la versión Python, cuyo `jt` apuntaba
//! al bloque ALLOW y por tanto NO bloqueaba en hosts reales):
//!   [0] LD W ABS seccomp_data.nr
//!   [1..N] JEQ K <nr_bloqueada>  -> jt salta al bloque EPERM (último)
//!   [N+1] RET ALLOW
//!   [N+2] RET ERRNO(EPERM)
//!
//! `jt` es relativo a la siguiente instrucción: jt = (indice_EPERM) - (i + 1).

use libc::{c_int, c_ushort};

// opcodes BPF (classic BPF)
const BPF_LD: u16 = 0x00;
const BPF_W: u16 = 0x00;
const BPF_ABS: u16 = 0x20;
const BPF_JMP: u16 = 0x05;
const BPF_JEQ: u16 = 0x10;
const BPF_K: u16 = 0x00;
const BPF_RET: u16 = 0x06;

const BPF_LD_W_ABS: u16 = BPF_LD | BPF_W | BPF_ABS; // 0x20
const BPF_JMP_JEQ_K: u16 = BPF_JMP | BPF_JEQ | BPF_K; // 0x15
const BPF_RET_K: u16 = BPF_RET | BPF_K; // 0x06

// acciones seccomp
const SECCOMP_RET_ALLOW: u32 = 0x7fff_0000;
const SECCOMP_RET_ERRNO: u32 = 0x0005_0000;
const EPERM: u32 = 1;
const PR_SET_SECCOMP: c_int = 22;
const SECCOMP_MODE_FILTER: c_int = 2;

/// struct sock_filter { u16 code; u8 jt; u8 jf; u32 k; } = 8 bytes
#[repr(C)]
#[derive(Clone, Copy)]
struct SockFilter {
    code: c_ushort,
    jt: u8,
    jf: u8,
    k: u32,
}

/// struct sock_fprog { u16 len; struct sock_filter *filter; }
/// En x86_64: u16 (2) + padding (6) + puntero (8) = 16 bytes. repr(C) lo alinea bien.
#[repr(C)]
struct SockFprog {
    len: u16,
    filter: *const SockFilter,
}

/// Syscalls a bloquear (x86_64). syscall numbers estables:
/// truncate 76, ftruncate 77 (impiden vaciar el log vía fd heredado), chmod 90,
/// fchmod 91, fchmodat 268, chown 92, fchown 93, lchown 94, fchownat 260,
/// setxattr 188, lsetxattr 189, fsetxattr 190.
const BLOCKED_NR: [c_ushort; 12] = [76, 77, 90, 91, 268, 92, 93, 94, 260, 188, 189, 190];

/// Instala el filtro seccomp vía prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog).
/// Si el entorno lo rechaza (EINVAL en contenedores, kernel sin soporte) devuelve Err
/// y el llamador decide degradar a Landlock-only.
pub fn install_seccomp() -> Result<(), std::io::Error> {
    let n = BLOCKED_NR.len();
    let mut prog: Vec<SockFilter> = Vec::with_capacity(n + 3);

    // [0] LD W ABS 0 -> cargar seccomp_data.nr
    prog.push(SockFilter {
        code: BPF_LD_W_ABS,
        jt: 0,
        jf: 0,
        k: 0,
    });

    // [1..N] JEQ: si nr == bloqueada, saltar a EPERM (última instrucción, índice n+2)
    let eperm_idx = (n + 2) as isize;
    for i in 1..=n {
        let jt = (eperm_idx - (i as isize + 1)) as u8;
        prog.push(SockFilter {
            code: BPF_JMP_JEQ_K,
            jt,
            jf: 0,
            k: BLOCKED_NR[i - 1] as u32,
        });
    }

    // [N+1] RET ALLOW (default)
    prog.push(SockFilter {
        code: BPF_RET_K,
        jt: 0,
        jf: 0,
        k: SECCOMP_RET_ALLOW,
    });

    // [N+2] RET ERRNO(EPERM) — alcanzado por los JEQ
    prog.push(SockFilter {
        code: BPF_RET_K,
        jt: 0,
        jf: 0,
        k: SECCOMP_RET_ERRNO | EPERM,
    });

    let prog_ptr = prog.as_ptr();
    let fprog = SockFprog {
        len: prog.len() as u16,
        filter: prog_ptr,
    };

    // mantiene vivo el buffer durante la llamada
    let ret = unsafe {
        libc::prctl(
            PR_SET_SECCOMP,
            SECCOMP_MODE_FILTER,
            &fprog as *const SockFprog,
            0,
            0,
        )
    };
    if ret < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}
