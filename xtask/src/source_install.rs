use std::{
    env, fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use crate::{
    metainfo_release_stamp::APPLICATION_ID,
    task_failure::TaskFailure,
    tool_commands::{required_variable, run_tool, tool_stdout},
};

const INSTALL_PREFIX_ARGUMENT: &str = "PREFIX=/usr";
const APPLICATION_BINARY: &str = "/usr/bin/lazaret";
const CLAMAV_ADMIN_BINARY: &str = "/usr/libexec/lazaret/lazaret-clamav-admin";
const COMPILED_SCHEMAS_PATH: &str = "/usr/share/glib-2.0/schemas/gschemas.compiled";
const DEFAULT_BASE_CLAMD_CONFIG: &str = "/etc/clamav/clamd.conf";
const MERGED_CLAMD_CONFIG_PATH: &str = "/run/lazaret/clamd.conf";
const INSTALLED_ADMIN_SERVICE_FILES: [&str; 8] = [
    "/usr/share/polkit-1/actions/page.codeberg.wvhulle.Lazaret.policy",
    "/usr/share/dbus-1/system.d/page.codeberg.wvhulle.Lazaret.ClamavAdmin.conf",
    "/usr/share/dbus-1/system-services/page.codeberg.wvhulle.Lazaret.ClamavAdmin.service",
    "/usr/lib/systemd/system/lazaret-clamav-admin.service",
    "/usr/lib/systemd/system/lazaret-settings-merge.service",
    "/usr/lib/systemd/system/lazaret-reduction-expiry.service",
    "/usr/lib/systemd/system/lazaret-reduction-expiry.timer",
    "/usr/lib/systemd/user/lazaret.service",
];

fn unresolved_shared_libraries(ldd_output: &str) -> Vec<&str> {
    ldd_output
        .lines()
        .filter(|ldd_line| ldd_line.contains("not found"))
        .map(str::trim)
        .collect()
}

fn compiled_schemas_contain_application(compiled_schemas: &[u8]) -> bool {
    compiled_schemas
        .windows(APPLICATION_ID.len())
        .any(|byte_window| byte_window == APPLICATION_ID.as_bytes())
}

fn installed_file_paths() -> impl Iterator<Item = &'static str> {
    [APPLICATION_BINARY, CLAMAV_ADMIN_BINARY]
        .into_iter()
        .chain(INSTALLED_ADMIN_SERVICE_FILES)
}

#[derive(Clone, Copy, Debug)]
enum ContainerPackageManager {
    AptGet,
    Dnf,
    Pacman,
}

impl ContainerPackageManager {
    const ALL: [Self; 3] = [Self::AptGet, Self::Dnf, Self::Pacman];

    const fn program_name(self) -> &'static str {
        match self {
            Self::AptGet => "apt-get",
            Self::Dnf => "dnf",
            Self::Pacman => "pacman",
        }
    }

    fn make_install_command(self) -> Command {
        let mut install_command = Command::new("sh");
        let install_script = match self {
            Self::AptGet => "apt-get update -qq && apt-get install -y -qq make",
            Self::Dnf => "dnf install -y --quiet make",
            Self::Pacman => "pacman -Sy --needed --noconfirm make",
        };
        install_command.args(["-c", install_script]);
        install_command
    }
}

fn program_runs(program: &Path) -> bool {
    Command::new(program)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|exit_status| exit_status.success())
}

fn install_make_when_missing() -> Result<(), TaskFailure> {
    if program_runs(Path::new("make")) {
        return Ok(());
    }
    let package_manager = ContainerPackageManager::ALL
        .into_iter()
        .find(|package_manager| program_runs(Path::new(package_manager.program_name())))
        .ok_or(TaskFailure::PackageManagerMissing)?;
    run_tool(
        package_manager.program_name(),
        &mut package_manager.make_install_command(),
    )
}

fn usable_cargo_program() -> Result<PathBuf, TaskFailure> {
    let path_cargo = PathBuf::from("cargo");
    if program_runs(&path_cargo) {
        return Ok(path_cargo);
    }
    run_tool(
        "rustup-init",
        Command::new("rustup-init").args([
            "-y",
            "--quiet",
            "--no-modify-path",
            "--default-toolchain",
            "none",
            "--profile",
            "minimal",
        ]),
    )?;
    Ok(PathBuf::from(required_variable("HOME")?).join(".cargo/bin/cargo"))
}

fn run_make_target(make_target: &str, cargo_program: &Path) -> Result<(), TaskFailure> {
    run_tool(
        "make",
        Command::new("make")
            .arg(make_target)
            .arg(INSTALL_PREFIX_ARGUMENT)
            .arg(format!("CARGO={}", cargo_program.display())),
    )
}

fn check_binary_libraries_resolve(binary_path: &Path) -> Result<(), TaskFailure> {
    let ldd_output = tool_stdout("ldd", Command::new("ldd").arg(binary_path))?;
    let unresolved_libraries = unresolved_shared_libraries(&ldd_output);
    if unresolved_libraries.is_empty() {
        Ok(())
    } else {
        Err(TaskFailure::SharedLibrariesUnresolved {
            library_lines: unresolved_libraries.join("; "),
        })
    }
}

fn check_merge_keeps_base_config(base_config_path: &Path) -> Result<(), TaskFailure> {
    fs::create_dir_all("/run/lazaret")?;
    run_tool(
        "lazaret-clamav-admin",
        Command::new(CLAMAV_ADMIN_BINARY).arg("merge"),
    )?;
    if fs::read(base_config_path)? == fs::read(MERGED_CLAMD_CONFIG_PATH)? {
        Ok(())
    } else {
        Err(TaskFailure::MergedConfigDiffers {
            base_config_path: base_config_path.to_path_buf(),
        })
    }
}

fn check_installed_files() -> Result<(), TaskFailure> {
    check_binary_libraries_resolve(Path::new(APPLICATION_BINARY))?;
    check_binary_libraries_resolve(Path::new(CLAMAV_ADMIN_BINARY))?;
    if !compiled_schemas_contain_application(&fs::read(COMPILED_SCHEMAS_PATH)?) {
        return Err(TaskFailure::CompiledSchemaMissing {
            application_id: APPLICATION_ID,
        });
    }
    match installed_file_paths().find(|installed_path| !Path::new(installed_path).exists()) {
        Some(installed_path) => Err(TaskFailure::InstalledFileMissing { installed_path }),
        None => Ok(()),
    }
}

fn check_uninstall_removed_files() -> Result<(), TaskFailure> {
    match installed_file_paths().find(|installed_path| Path::new(installed_path).exists()) {
        Some(installed_path) => Err(TaskFailure::UninstalledFileRemains { installed_path }),
        None => Ok(()),
    }
}

pub fn check_source_install() -> Result<(), TaskFailure> {
    install_make_when_missing()?;
    run_make_target("deps", Path::new("cargo"))?;
    let cargo_program = usable_cargo_program()?;
    run_make_target("build", &cargo_program)?;
    run_make_target("install", &cargo_program)?;
    check_installed_files()?;
    let base_config_path = env::var_os("CLAMD_CONFIG")
        .map_or_else(|| PathBuf::from(DEFAULT_BASE_CLAMD_CONFIG), PathBuf::from);
    check_merge_keeps_base_config(&base_config_path)?;
    run_make_target("uninstall", &cargo_program)?;
    check_uninstall_removed_files()
}

#[cfg(test)]
mod source_install_tests {
    use super::*;

    #[test]
    fn lists_only_unresolved_shared_libraries() {
        let ldd_output =
            "\tlibc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x7f)\n\tlibgtk-4.so.1 => not found\n";
        assert_eq!(
            unresolved_shared_libraries(ldd_output),
            vec!["libgtk-4.so.1 => not found"]
        );
    }

    #[test]
    fn finds_application_id_inside_compiled_schemas() {
        let compiled_schemas =
            [b"\0\x01binary".as_slice(), APPLICATION_ID.as_bytes(), b"\0"].concat();
        assert!(compiled_schemas_contain_application(&compiled_schemas));
        assert!(!compiled_schemas_contain_application(b"org.gnome.other\0"));
    }

    #[test]
    fn checks_both_binaries_and_every_admin_service_file() {
        let checked_paths = installed_file_paths().collect::<Vec<_>>();
        assert_eq!(checked_paths.len(), 10);
        assert!(checked_paths.contains(&APPLICATION_BINARY));
        assert!(checked_paths.contains(&"/usr/lib/systemd/system/lazaret-settings-merge.service"));
    }
}
