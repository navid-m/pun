// cpanm installation utilities

use std::process::Command;

pub fn ensure_cpanm() -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        return Err("cpanm not found. Install App::cpanminus manually.".to_string());
    }

    #[cfg(not(target_os = "windows"))]
    {
        println!("cpanm not found. Installing via system package manager...");

        let package_managers: &[(&[&str], &str)] = &[
            (
                &["which", "apt-get"],
                "perl-App-cpanminus",
            ),
            (
                &["which", "dnf"],
                "perl-App-cpanminus",
            ),
            (
                &["which", "yum"],
                "perl-App-cpanminus",
            ),
            (
                &["which", "pacman"],
                "perl-app-cpanminus",
            ),
            (
                &["which", "zypper"],
                "perl-App-cpanminus",
            ),
            (
                &["which", "brew"],
                "cpanminus",
            ),
        ];

        for (check_cmd, package) in package_managers {
            let check = Command::new(check_cmd[0])
                .args(&check_cmd[1..])
                .output();

            if let Ok(output) = check {
                if output.status.success() {
                    let install_cmd = match check_cmd[0] {
                        "apt-get" => Command::new("sudo")
                            .args(["apt-get", "install", "-y", package])
                            .output(),
                        "dnf" => Command::new("sudo")
                            .args(["dnf", "install", "-y", package])
                            .output(),
                        "yum" => Command::new("sudo")
                            .args(["yum", "install", "-y", package])
                            .output(),
                        "pacman" => Command::new("sudo")
                            .args(["pacman", "-S", "--noconfirm", package])
                            .output(),
                        "zypper" => Command::new("sudo")
                            .args(["zypper", "install", "-y", package])
                            .output(),
                        "brew" => Command::new("brew")
                            .args(["install", package])
                            .output(),
                        _ => unreachable!(),
                    };

                    if let Ok(result) = install_cmd {
                        if result.status.success() {
                            return Ok(());
                        }
                    }
                }
            }
        }

        return Err("Could not detect package manager. Install cpanminus manually.".to_string());
    }
}
