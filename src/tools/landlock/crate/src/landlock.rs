// SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
// SPDX-License-Identifier: MPL-2.0

//! Landlock syscalls (444/445/446) + prctl(NO_NEW_PRIVS) sin dependencias de ctypes.
//! Estructuras con `#[repr(C)]` → el layout coincide con el que el kernel espera
//! (el problema de padding/alignment que dio bugs en la versión Python se resuelve solo).

use libc::{c_int, c_long, c_uint, c_ulong, c_void};

// --- Syscall numbers (x86_64, estables desde 5.13) ---
const SYS_LANDLOCK_CREATE_RULESET: c_long = 444;
const SYS_LANDLOCK_ADD_RULE: c_long = 445;
const SYS_LANDLOCK_RESTRICT_SELF: c_long = 446;
const LANDLOCK_CREATE_RULESET_VERSION: c_uint = 1;
const LANDLOCK_RULE_PATH_BENEATH: c_uint = 1;

// --- Bits LANDLOCK_ACCESS_FS_* (uapi/linux/landlock.h) ---
pub const EXECUTE: c_ulong = 1 << 0;
pub const WRITE_FILE: c_ulong = 1 << 1;
pub const READ_FILE: c_ulong = 1 << 2;
pub const READ_DIR: c_ulong = 1 << 3;
pub const REMOVE_DIR: c_ulong = 1 << 4;
pub const REMOVE_FILE: c_ulong = 1 << 5;
pub const MAKE_CHAR: c_ulong = 1 << 6;
pub const MAKE_DIR: c_ulong = 1 << 7;
pub const MAKE_REG: c_ulong = 1 << 8;
pub const MAKE_SOCK: c_ulong = 1 << 9;
pub const MAKE_FIFO: c_ulong = 1 << 10;
pub const MAKE_BLOCK: c_ulong = 1 << 11;
pub const MAKE_SYM: c_ulong = 1 << 12;
pub const REFER: c_ulong = 1 << 13;
pub const TRUNCATE: c_ulong = 1 << 14;
pub const IOCTL_DEV: c_ulong = 1 << 15;

/// struct landlock_ruleset_attr { u64 handled_access_fs; u64 handled_access_net; }
/// Pasamos size=8 (solo campo FS) → compatible con cualquier ABI >=1.
#[repr(C)]
struct LandlockRulesetAttr {
    handled_access_fs: c_ulong,
    handled_access_net: c_ulong,
}

/// struct landlock_path_beneath_attr { u64 allowed_access_fs; s32 parent_fd; } + padding
/// repr(C) alinea: u64 (offset 0) + s32 (offset 8) + 4 pad = 16 bytes. Layout correcto.
#[repr(C)]
struct LandlockPathBeneathAttr {
    allowed_access_fs: c_ulong,
    parent_fd: c_int,
}

/// landlock_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION) → ABI soportada
pub fn landlock_abi() -> Result<c_long, std::io::Error> {
    let ret = unsafe {
        libc::syscall(
            SYS_LANDLOCK_CREATE_RULESET,
            std::ptr::null::<c_void>(),
            0 as libc::size_t,
            LANDLOCK_CREATE_RULESET_VERSION,
        )
    };
    if ret < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(ret)
    }
}

/// Crea el ruleset declarando qué accesos vamos a gobernar (handled).
pub fn landlock_create_ruleset(handled_fs: c_ulong) -> Result<c_int, std::io::Error> {
    let attr = LandlockRulesetAttr {
        handled_access_fs: handled_fs,
        handled_access_net: 0,
    };
    let ret = unsafe {
        libc::syscall(
            SYS_LANDLOCK_CREATE_RULESET,
            &attr as *const _ as *const libc::c_void,
            std::mem::size_of::<LandlockRulesetAttr>() as libc::size_t,
            0 as libc::c_uint,
        )
    };
    if ret < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(ret as c_int)
    }
}

/// Agrega una regla path-beneath: permite `allowed_fs` bajo el path dado.
pub fn landlock_add_path_rule(
    ruleset_fd: c_int,
    allowed_fs: c_ulong,
    path: &str,
) -> Result<(), std::io::Error> {
    let c_path = std::ffi::CString::new(path)
        .map_err(|_| std::io::Error::new(std::io::ErrorKind::InvalidInput, "path contiene NUL"))?;
    let parent_fd = unsafe { libc::open(c_path.as_ptr(), libc::O_PATH | libc::O_RDONLY) };
    if parent_fd < 0 {
        return Err(std::io::Error::last_os_error());
    }
    let attr = LandlockPathBeneathAttr {
        allowed_access_fs: allowed_fs,
        parent_fd,
    };
    let ret = unsafe {
        libc::syscall(
            SYS_LANDLOCK_ADD_RULE,
            ruleset_fd,
            LANDLOCK_RULE_PATH_BENEATH,
            &attr as *const _ as *const libc::c_void,
            0 as libc::c_uint,
        )
    };
    let err = std::io::Error::last_os_error();
    unsafe { libc::close(parent_fd) };
    if ret < 0 {
        Err(err)
    } else {
        Ok(())
    }
}

/// Sella el proceso: aplica el ruleset. Irreversible.
pub fn landlock_restrict_self(ruleset_fd: c_int) -> Result<(), std::io::Error> {
    let ret = unsafe { libc::syscall(SYS_LANDLOCK_RESTRICT_SELF, ruleset_fd, 0 as libc::c_uint) };
    if ret < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}

/// prctl(PR_SET_NO_NEW_PRIVS, 1) — obligatorio antes de seccomp; impide escalar.
pub fn no_new_privs() -> Result<(), std::io::Error> {
    let ret = unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) };
    if ret < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}
