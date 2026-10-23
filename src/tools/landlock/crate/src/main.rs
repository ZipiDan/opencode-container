//! landlock_rosh — shell/comando encerrado por Landlock en SOLO LECTURA.
//! Versión en Rust. Binario estático (musl), sin Python.
//!
//! Flujo:
//!   --install-log          → instala integración de logging con el SO (SIN sandbox, root)
//!   --uninstall-log        → operación inversa de --install-log
//!   --install-shell        → instala binario + wrapper nolog como shells del sistema
//!                            (/usr/local/bin + /etc/shells; SIN sandbox, root, idempotente)
//!   --uninstall-shell      → operación inversa de --install-shell (aborta si hay usuarios)
//!   --install-ssh          → instala shell + placeholder comentado en
//!                            /root/.ssh/authorized_keys (informe jefe §5)
//!   --uninstall-ssh        → quita placeholder comentado + shells del sistema
//!   --print-ssh-line       → imprime la línea sugerida para authorized_keys y sale
//!   --no-log               → deshabilita auditoría de comandos aunque esté instalada
//!   --log-only             → ejecuta SIN sandbox; solo deja traza en el log
//!   -c "comando"           → ejecuta ese comando (gana sobre SSH_ORIGINAL_COMMAND)
//!   --version, -V          → muestra versión y sale
//!   --help, -h             → muestra resumen de uso y sale
//!   Landlock disponible   → ruleset Landlock + seccomp (read-only real por kernel)
//!   kernel < 5.13 (ENOSYS) → fallback automático a bubblewrap (bwrap): mount ns
//!                            read-only (/, /dev, /sys RO; /tmp, /var/tmp writable)
//!   bwrap no instalado    → INFO con el comando de instalación según distro
//!
//! Auditoría v1.6: cada comando ejecutado se loguea por journald o archivo
//! (/var/log/landlock_rosh) con timestamp, host, user, IP origen y exit code.

mod audit;
mod bwrap;
mod landlock;
mod osinfo;
mod seccomp;
mod shell;

use audit::AuditCtx;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::process::Command;

const VERSION: &str = "1.9.0";

// --- Paths writable POR DEFECTO (editar aquí si cambian las necesidades) ---
// Directorios donde write/mkdir/rm están permitidos:
const DEFAULT_WRITABLE_PATHS: &[&str] = &["/tmp", "/var/tmp"];
// Nodos donde solo write/truncate están permitidos (no create/remove):
const DEFAULT_WRITABLE_NODES: &[&str] = &["/dev/null", "/dev/zero", "/dev/tty"];
// Override opcional por env (separado por ':') si se necesita sin recompilar:
const ENV_WRITABLE_PATHS: &str = "LANDLOCK_WRITABLE_PATHS";
const ENV_WRITABLE_NODES: &str = "LANDLOCK_WRITABLE_NODES";
// Forzar apagado de seccomp con LANDLOCK_NO_SECCOMP=1
const ENV_NO_SECCOMP: &str = "LANDLOCK_NO_SECCOMP";

// --- Prompt interactivo: rcfile que define PS1 ---
// PS1 del driver (Calisto) con "(rosh)" insertado despues del host (\h), antes de los ":".
// Colores ANSI hardcodeados (sin depender de `tput`): bold=\033[1m, reset=\033[0m.
const ROSH_RC_PATH: &str = "/tmp/landlock_rosh.rc";
const ROSH_RC_CONTENT: &str = r#"PS1='[\A]\[\033[1m\]\[\033[0m\]\[\033[38;5;6m\]\u\[\033[0m\]\[\033[0m\]\[\033[38;5;15m\]@\[\033[1m\]\[\033[0m\]\[\033[38;5;9m\]\h(rosh)\[\033[0m\]\[\033[0m\]\[\033[38;5;15m\]:\w > \[\033[0m\]'
"#;

/// Contenido completo del rcfile: PS1 + hook de auditoría si hay backend activo.
fn rosh_rc_content(audit: &AuditCtx) -> String {
    let mut content = ROSH_RC_CONTENT.to_string();
    if let Some(hook) = audit.rc_hook() {
        content.push_str(&hook);
    }
    content
}

fn print_help() {
    println!(
        "landlock_rosh {VERSION} — shell/read-only sandbox por Landlock (kernel) o bubblewrap"
    );
    println!();
    println!("USO:");
    println!("  landlock_rosh                      Shell interactiva (Landlock read-only)");
    println!("  landlock_rosh -c \"comando\"         Ejecuta un comando (o SSH_ORIGINAL_COMMAND)");
    println!();
    println!("FLAGS ADMINISTRATIVAS (root, sin sandbox):");
    println!("  --install-log      Instala integración de logging con el SO");
    println!("  --uninstall-log    Desinstala la integración de logging");
    println!("  --install-shell    Instala binario + wrapper como shells del sistema");
    println!("  --uninstall-shell  Desinstala las shells del sistema");
    println!(
        "  --install-ssh      Instala shell + placeholder comentado en /root/.ssh/authorized_keys"
    );
    println!("  --uninstall-ssh    Desinstala placeholder + shells del sistema");
    println!();
    println!("FLAGS DE USO:");
    println!("  --print-ssh-line   Imprime la línea sugerida para authorized_keys y sale");
    println!("                     Opciones: --mode ro|log  --pubkey ARCHIVO");
    println!("  --no-log           Deshabilita auditoría en esta invocación");
    println!("  --log-only         Sin sandbox: permite escritura y solo deja traza");
    println!("  --version, -V      Muestra versión y sale");
    println!("  --help, -h         Muestra esta ayuda y sale");
    println!();
    println!("KERNEL < 5.13:");
    println!("  Fallback automático a bubblewrap (bwrap). Landlock no soportado.");
}

fn main() {
    // args_os + lossy: un argumento no-UTF8 no debe panickear el launcher.
    let args: Vec<String> = std::env::args_os()
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    if args.iter().any(|a| a == "--version" || a == "-V") {
        println!("landlock_rosh {VERSION}");
        std::process::exit(0);
    }

    // --help: resumen de uso y flags.
    if args.iter().any(|a| a == "--help" || a == "-h") {
        print_help();
        std::process::exit(0);
    }

    // --print-ssh-line: asistencia de instalación; no toca nada del sistema.
    if args.iter().any(|a| a == "--print-ssh-line") {
        let mode = option_value(&args, "--mode").unwrap_or_else(|| "ro".to_string());
        let pubkey = option_value(&args, "--pubkey");
        shell::cli_print_ssh_line(&mode, pubkey.as_deref());
    }

    // Flags administrativas de logging: corren SIN sandbox (necesitan tocar /etc).
    // Si se invocan desde adentro de la jaula fallarán al escribir → error natural.
    if args.iter().any(|a| a == "--install-log") {
        audit::cli_install();
    }
    if args.iter().any(|a| a == "--uninstall-log") {
        audit::cli_uninstall();
    }
    // Flags administrativas de shells: idem, corren SIN sandbox (tocan /usr/local/bin y /etc).
    if args.iter().any(|a| a == "--install-shell") {
        shell::cli_install_shell();
    }
    if args.iter().any(|a| a == "--uninstall-shell") {
        shell::cli_uninstall_shell();
    }
    // Flags de integración SSH (shell + authorized_keys).
    if args.iter().any(|a| a == "--install-ssh") {
        shell::cli_install_ssh();
    }
    if args.iter().any(|a| a == "--uninstall-ssh") {
        shell::cli_uninstall_ssh();
    }

    // Modo de ejecución: comando (`-c`) o shell interactiva.
    // `-c` gana sobre SSH_ORIGINAL_COMMAND: es el contrato de login shell de sshd
    // y permite la invocación manual (`landlock_rosh -c "df -h"`).
    let cmd_ssh = match command_from_args(&args) {
        Some(cmd) => cmd,
        None => match std::env::var_os("SSH_ORIGINAL_COMMAND") {
            Some(v) => match v.into_string() {
                Ok(s) => s,
                Err(no_utf8) => {
                    let lossy = no_utf8.to_string_lossy().into_owned();
                    eprintln!(
                        "[landlock] aviso: SSH_ORIGINAL_COMMAND no era UTF-8 valido; se ejecuta con perdida de datos"
                    );
                    lossy
                }
            },
            None => String::new(),
        },
    };
    let no_log = args.iter().any(|a| a == "--no-log");
    let log_only = args.iter().any(|a| a == "--log-only");
    if log_only && no_log {
        fatal("--log-only y --no-log son incompatibles: elegí uno");
    }
    if log_only {
        run_log_only(&cmd_ssh);
    }

    match landlock::landlock_abi() {
        Ok(abi) if abi >= 1 && !force_bwrap() => run_landlock(abi, &cmd_ssh, no_log),
        Ok(abi) if force_bwrap() => {
            eprintln!(
                "[landlock] INFO: LANDLOCK_FORCE_BWRAP=1 activo (Landlock ABI {abi} disponible pero se fuerza bwrap)."
            );
            run_bwrap_fallback(&cmd_ssh, no_log);
        }
        Ok(abi) => {
            fatal(&format!(
                "Landlock no disponible en este kernel (ABI={abi})"
            ));
        }
        Err(e) if e.raw_os_error() == Some(libc::ENOSYS) => {
            // Kernel sin Landlock (< 5.13): fallback automático a bubblewrap.
            eprintln!(
                "[landlock] INFO: Landlock no soportado por este kernel (ENOSYS, kernel {}).",
                kernel_release()
            );
            run_bwrap_fallback(&cmd_ssh, no_log);
        }
        Err(e) => {
            fatal(&format!("Landlock no disponible: {e}"));
        }
    }
}

/// Valor de una opción con forma `--flag valor` (None si falta o no está).
fn option_value(args: &[String], name: &str) -> Option<String> {
    let idx = args.iter().position(|a| a == name)?;
    args.get(idx + 1).cloned()
}

/// Comando pedido con `-c`; si falta el valor, es un error de uso.
fn command_from_args(args: &[String]) -> Option<String> {
    let idx = args.iter().position(|a| a == "-c")?;
    match args.get(idx + 1) {
        Some(cmd) => Some(cmd.clone()),
        None => fatal("-c requiere un comando"),
    }
}

/// Modo solo auditoría: sin Landlock/seccomp. Permite escritura y deja traza.
/// NO es una barrera de seguridad: únicamente registra lo ejecutado.
fn run_log_only(cmd_ssh: &str) -> ! {
    eprintln!("[landlock] AVISO: --log-only desactiva el sandbox; solo se registra el comando");
    let mut audit_ctx = AuditCtx::open(false, "log-only");
    if !cmd_ssh.is_empty() {
        audit_ctx.log_cmd_start(cmd_ssh);
    } else {
        audit_ctx.log_session_start();
    }
    finish(&mut audit_ctx, cmd_ssh);
}

/// Modo Landlock: ruleset read-only por kernel + seccomp (gap chmod/chown/setxattr).
fn run_landlock(abi: i64, cmd_ssh: &str, no_log: bool) -> ! {
    // Auditoría: abrir recurso ANTES de sellar (el fd abierto sobrevive al sandbox).
    let mode = format!("landlock-abi{abi}");
    let mut audit_ctx = AuditCtx::open(no_log, &mode);
    if !cmd_ssh.is_empty() {
        audit_ctx.log_cmd_start(cmd_ssh);
    } else {
        audit_ctx.log_session_start();
    }

    let handled = compute_handled();
    let handled = adjust_handled_for_abi(handled, abi);

    let fd = match landlock::landlock_create_ruleset(handled) {
        Ok(fd) => fd,
        Err(e) => fatal(&format!("landlock_create_ruleset: {e}")),
    };

    // Leer/ejecutar en todo /.
    let allowed_read_exec = landlock::READ_FILE | landlock::READ_DIR | landlock::EXECUTE;
    add_rule_or_fatal(fd, allowed_read_exec, "/", "regla raíz /");

    // Escritura solo en paths writable por defecto.
    let write_full = landlock::WRITE_FILE
        | landlock::TRUNCATE
        | landlock::MAKE_REG
        | landlock::MAKE_DIR
        | landlock::REMOVE_FILE
        | landlock::REMOVE_DIR
        | landlock::REFER;
    let write_node = landlock::WRITE_FILE | landlock::TRUNCATE;

    let writable_paths = split_env_or_default(ENV_WRITABLE_PATHS, DEFAULT_WRITABLE_PATHS);
    for p in &writable_paths {
        add_rule_or_warn(fd, write_full & handled, p, &format!("writable path {p}"));
    }

    let writable_nodes = split_env_or_default(ENV_WRITABLE_NODES, DEFAULT_WRITABLE_NODES);
    for n in &writable_nodes {
        if std::path::Path::new(n).exists() {
            add_rule_or_warn(fd, write_node & handled, n, &format!("nodo {n}"));
        }
    }

    // Sellar: NO_NEW_PRIVS + restrict_self (irreversible).
    if let Err(e) = landlock::no_new_privs() {
        fatal(&format!("prctl NO_NEW_PRIVS: {e}"));
    }
    if let Err(e) = landlock::landlock_restrict_self(fd) {
        fatal(&format!("landlock_restrict_self: {e}"));
    }
    unsafe { libc::close(fd) };

    // seccomp: bloquear chmod/chown/setxattr (gap de Landlock).
    let seccomp_estado = install_seccomp_or_degrade();

    eprintln!("[landlock] ABI={abi} seccomp={seccomp_estado}");
    finish(&mut audit_ctx, cmd_ssh);
}

/// Ejecuta el comando SSH (spawn+wait con log de exit) o lanza shell interactiva.
/// En modo comando NO usamos exec(): el launcher espera al hijo para auditar
/// el código de salida y propagarlo al cliente SSH (equivalente: sin job control).
fn finish(audit_ctx: &mut AuditCtx, cmd_ssh: &str) -> ! {
    if !cmd_ssh.is_empty() {
        eprintln!("[landlock] modo comando SSH: {}", truncate(cmd_ssh, 120));
        let status = Command::new("/bin/bash").arg("-c").arg(cmd_ssh).status();
        let code = exit_code_of(status);
        audit_ctx.log_cmd_end(cmd_ssh, code);
        std::process::exit(code);
    }
    eprintln!("[landlock] modo interactivo (shell)");
    exec_interactive_shell(audit_ctx);
}

/// Código de salida propagable: exit del hijo, o 128+señal si murió por señal.
fn exit_code_of(status: std::io::Result<std::process::ExitStatus>) -> i32 {
    use std::os::unix::process::ExitStatusExt;
    match status {
        Ok(s) => s
            .code()
            .or_else(|| s.signal().map(|sig| 128 + sig))
            .unwrap_or(1),
        Err(e) => {
            eprintln!("[landlock] FATAL: no pude lanzar /bin/bash: {e}");
            127
        }
    }
}

/// Shell interactiva con el prompt del driver (PS1 con "(rosh)" tras el host).
/// Si hay auditoría activa, hereda el fd del log (fd 9) y exporta las variables
/// que usa el hook PROMPT_COMMAND generado dentro del rcfile.
fn exec_interactive_shell(audit_ctx: &AuditCtx) -> ! {
    let content = rosh_rc_content(audit_ctx);
    match std::fs::write(ROSH_RC_PATH, &content) {
        Ok(()) => {
            let _ = std::fs::set_permissions(ROSH_RC_PATH, std::fs::Permissions::from_mode(0o600));
            let mut cmd = Command::new("/bin/bash");
            cmd.args(["--noprofile", "--rcfile", ROSH_RC_PATH, "-i"]);
            apply_audit_env(audit_ctx, &mut cmd);
            let err = cmd.exec();
            fatal(&format!("exec /bin/bash: {err}"));
        }
        Err(e) => {
            eprintln!("[landlock] aviso: no se pudo escribir {ROSH_RC_PATH} ({e}), prompt default");
            exec_or_fatal("/bin/bash", &["--norc", "--noprofile"]);
        }
    }
}

/// Prepara fd heredable + variables de entorno para el hook bash (si hay auditoría).
fn apply_audit_env(audit_ctx: &AuditCtx, cmd: &mut Command) {
    if let Some(fd) = audit_ctx.prepare_inherit_fd() {
        cmd.env("ROSH_LOG_FD", fd.to_string());
        cmd.env("ROSH_SRC", &audit_ctx.meta.src);
        cmd.env("ROSH_MODE", &audit_ctx.meta.mode);
    }
}

/// Modo bubblewrap: fallback para kernels < 5.13. Mount ns read-only por VFS.
fn run_bwrap_fallback(cmd_ssh: &str, no_log: bool) -> ! {
    // Auditoría: abrir antes de lanzar bwrap (el launcher NO está sandboxeado aquí).
    let mut audit_ctx = AuditCtx::open(no_log, "bwrap");
    if !cmd_ssh.is_empty() {
        audit_ctx.log_cmd_start(cmd_ssh);
    } else {
        audit_ctx.log_session_start();
    }

    // Confirmar que bwrap existe; si no, indicar el comando de instalación según distro.
    if !command_exists("bwrap") {
        let kernel = kernel_release();
        let install = bwrap::install_hint().unwrap_or_else(|| {
            "instale bubblewrap desde los repositorios de su distribucion".to_string()
        });
        eprintln!("[landlock] INFO: este kernel ({kernel}) no soporta Landlock y bubblewrap (bwrap) no esta instalado.");
        eprintln!("[landlock] INFO: instale bubblewrap para habilitar el modo de compatibilidad: {install}");
        eprintln!(
            "[landlock] INFO: alternativa: actualizar el kernel a >= 5.13 para usar Landlock."
        );
        std::process::exit(1);
    }

    eprintln!("[landlock] INFO: realizando fallback a bubblewrap (bwrap) — modo read-only por mount namespace.");

    // seccomp (auto-degradable): aporta bloqueo de chmod/chown/setxattr dentro del sandbox.
    let _seccomp_estado = install_seccomp_or_degrade();

    if !cmd_ssh.is_empty() {
        eprintln!("[landlock] modo comando SSH: {}", truncate(cmd_ssh, 120));
        let mut child_cmd = bwrap::build_bwrap_cmd(cmd_ssh);
        let status = child_cmd.status();
        let code = exit_code_of(status);
        audit_ctx.log_cmd_end(cmd_ssh, code);
        std::process::exit(code);
    } else {
        eprintln!("[landlock] aviso: job control desactivado en modo bwrap (Ctrl+Z/fg/bg no disponibles) — esperado.");
        let inner = format!(
            "printf '%s' \"$ROSH_RC\" > {ROSH_RC_PATH} && exec /bin/bash --noprofile --rcfile {ROSH_RC_PATH} -i"
        );
        exec_bwrap_interactive(&mut audit_ctx, &inner);
    }
}

/// Lanza bash interactivo dentro del sandbox bwrap, filtrando los mensajes de arranque
/// de bash (job control) para reemplazarlos por el aviso corto del launcher.
fn exec_bwrap_interactive(audit_ctx: &mut AuditCtx, inner: &str) -> ! {
    use std::io::BufRead;
    use std::process::Stdio;

    let mut cmd = bwrap::build_bwrap_cmd(inner);
    cmd.env("ROSH_RC", rosh_rc_content(audit_ctx));
    apply_audit_env(audit_ctx, &mut cmd);
    cmd.stdin(Stdio::inherit());
    cmd.stdout(Stdio::inherit());
    // stderr a pipe: filtramos los mensajes de arranque de bash (job control).
    cmd.stderr(Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => fatal(&format!("spawn bwrap: {e}")),
    };
    let stderr = child.stderr.take().expect("stderr pipe");

    std::thread::spawn(move || {
        let mut line = String::new();
        let mut reader = std::io::BufReader::new(stderr);
        loop {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) => break,
                Ok(_) => {
                    let t = line.trim_end();
                    // Los 2 mensajes de arranque de bash (job control) se descartan:
                    // el launcher ya mostró el aviso corto.
                    if t.contains("no job control in this shell")
                        || t.contains("no hay control de trabajos")
                        || t.contains("cannot set terminal process group")
                        || t.contains("no se puede establecer el grupo de proceso de terminal")
                    {
                        continue;
                    }
                    eprint!("{line}");
                }
                Err(_) => break,
            }
        }
    });

    let status = child.wait();
    match status {
        Ok(st) => std::process::exit(st.code().unwrap_or(1)),
        Err(e) => fatal(&format!("wait bwrap: {e}")),
    }
}

/// Bits FS a gobernar (incluyen los reads que permitimos y los writes que negamos).
fn compute_handled() -> u64 {
    landlock::READ_FILE
        | landlock::READ_DIR
        | landlock::EXECUTE
        | landlock::WRITE_FILE
        | landlock::TRUNCATE
        | landlock::REMOVE_FILE
        | landlock::REMOVE_DIR
        | landlock::MAKE_REG
        | landlock::MAKE_DIR
        | landlock::MAKE_CHAR
        | landlock::MAKE_SOCK
        | landlock::MAKE_FIFO
        | landlock::MAKE_BLOCK
        | landlock::MAKE_SYM
        | landlock::REFER
        | landlock::IOCTL_DEV
}

/// Quita los bits que la ABI del kernel no soporta (quedan sin restringir).
fn adjust_handled_for_abi(mut handled: u64, abi: i64) -> u64 {
    if abi < 5 {
        handled &= !landlock::IOCTL_DEV;
    }
    if abi < 2 {
        handled &= !landlock::REFER;
    }
    if abi < 3 {
        handled &= !landlock::TRUNCATE;
    }
    handled
}

fn add_rule_or_fatal(fd: i32, allowed: u64, path: &str, ctx: &str) {
    if let Err(e) = landlock::landlock_add_path_rule(fd, allowed, path) {
        fatal(&format!("{ctx}: {e}"));
    }
}

fn add_rule_or_warn(fd: i32, allowed: u64, path: &str, ctx: &str) {
    if let Err(e) = landlock::landlock_add_path_rule(fd, allowed, path) {
        eprintln!("[landlock] AVISO {ctx}: {e}");
    }
}

/// Lee env var; si no está definida usa el default. Separa por ':'.
fn split_env_or_default(var: &str, default: &[&str]) -> Vec<String> {
    match std::env::var(var) {
        Ok(v) => v
            .split(':')
            .map(|s| s.to_string())
            .filter(|s| !s.is_empty())
            .collect(),
        Err(_) => default.iter().map(|s| s.to_string()).collect(),
    }
}

fn install_seccomp_or_degrade() -> String {
    if std::env::var(ENV_NO_SECCOMP)
        .map(|v| v == "1")
        .unwrap_or(false)
    {
        "desactivado (forzado LANDLOCK_NO_SECCOMP=1)".to_string()
    } else {
        match seccomp::install_seccomp() {
            Ok(()) => "activo (chmod/chown/setxattr bloqueados)".to_string(),
            Err(e) => format!("NO disponible ({e}) -> solo restriccion de mount/landlock"),
        }
    }
}

fn exec_or_fatal(program: &str, args: &[&str]) -> ! {
    let err = Command::new(program).args(args).exec();
    fatal(&format!("exec {program}: {err}"));
}

/// ¿Existe el binario en el PATH?
fn command_exists(name: &str) -> bool {
    let path = std::env::var("PATH").unwrap_or_default();
    for dir in path.split(':') {
        if dir.is_empty() {
            continue;
        }
        let full = std::path::Path::new(dir).join(name);
        if full.is_file() && is_executable(&full) {
            return true;
        }
    }
    false
}

/// Forzar el fallback a bwrap (útil para testing y para elegir mecanismo sin recompilar).
fn force_bwrap() -> bool {
    std::env::var("LANDLOCK_FORCE_BWRAP")
        .map(|v| v == "1")
        .unwrap_or(false)
}

fn is_executable(p: &std::path::Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p)
        .map(|m| m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

fn truncate(s: &str, max: usize) -> &str {
    if s.len() <= max {
        s
    } else {
        &s[..max]
    }
}

/// Versión del kernel en ejecución.
fn kernel_release() -> String {
    std::fs::read_to_string("/proc/sys/kernel/osrelease")
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|_| "desconocido".to_string())
}

fn fatal(msg: &str) -> ! {
    eprintln!("[landlock] FATAL: {msg}");
    std::process::exit(1);
}
