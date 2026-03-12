// Environment and Perl installation management

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::globs::{PERLS_DIR, PROJECT_CONFIG, PROJECT_LOCAL_CONFIG, PUN_HOME};
use crate::projects::{read_punlrc, read_punrc, update_punrc_version};

pub fn get_pun_home() -> PathBuf {
    let home = env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(PUN_HOME)
}

pub fn get_perls_dir() -> PathBuf {
    get_pun_home().join(PERLS_DIR)
}

pub fn get_perl_path(version: &str) -> PathBuf {
    get_perls_dir().join(version)
}

pub fn show_version() {
    println!("v0.0.1");
}

pub fn ensure_pun_home() -> std::io::Result<()> {
    let pun_home = get_pun_home();
    if !pun_home.exists() {
        fs::create_dir_all(&pun_home)?;
    }

    let perls_dir = get_perls_dir();
    if !perls_dir.exists() {
        fs::create_dir_all(&perls_dir)?;
    }

    Ok(())
}

pub fn install_perl(version: &str) -> Result<(), String> {
    ensure_pun_home().map_err(|e| e.to_string())?;

    let perl_path = get_perl_path(version);

    if perl_path.exists() {
        println!(
            "Perl {} is already installed at {}",
            version,
            perl_path.display()
        );
        return Ok(());
    }

    println!("Installing Perl {}...", version);
    println!("This will download and compile Perl from source.");

    let temp_dir = env::temp_dir().join(format!("pun-build-{}", version));
    if temp_dir.exists() {
        fs::remove_dir_all(&temp_dir).map_err(|e| e.to_string())?;
    }
    fs::create_dir_all(&temp_dir).map_err(|e| e.to_string())?;

    let tarball = format!("perl-{}.tar.gz", version);
    let url = format!("https://www.cpan.org/src/5.0/{}", tarball);

    println!("Downloading from {}", url);
    let download_status = Command::new("curl")
        .args(["-L", "-o"])
        .arg(temp_dir.join(&tarball))
        .arg(&url)
        .status()
        .map_err(|e| e.to_string())?;

    if !download_status.success() {
        return Err(format!("Failed to download Perl {}", version));
    }

    println!("Extracting...");
    let extract_status = Command::new("tar")
        .args(["-xzf", &tarball])
        .current_dir(&temp_dir)
        .status()
        .map_err(|e| e.to_string())?;

    if !extract_status.success() {
        return Err("Failed to extract Perl tarball".to_string());
    }

    let build_dir = temp_dir.join(format!("perl-{}", version));
    println!("Configuring...");

    let config_status = Command::new("sh")
        .args(["Configure", "-des"])
        .arg(format!("-Dprefix={}", perl_path.display()))
        .current_dir(&build_dir)
        .status()
        .map_err(|e| e.to_string())?;

    if !config_status.success() {
        return Err("Failed to configure Perl".to_string());
    }

    println!("Building (this may take a while)...");
    let make_status = Command::new("make")
        .arg("-j4")
        .current_dir(&build_dir)
        .status()
        .map_err(|e| e.to_string())?;

    if !make_status.success() {
        return Err("Failed to build Perl".to_string());
    }

    println!("Installing...");
    let install_status = Command::new("make")
        .arg("install")
        .current_dir(&build_dir)
        .status()
        .map_err(|e| e.to_string())?;

    if !install_status.success() {
        return Err("Failed to install Perl".to_string());
    }

    println!("Installing cpanm...");
    let perl_bin = perl_path.join("bin").join("perl");
    let _ = Command::new("curl")
        .arg("-L")
        .arg("https://cpanmin.us")
        .stdout(std::process::Stdio::piped())
        .spawn()
        .and_then(|child| {
            Command::new(&perl_bin)
                .arg("-")
                .arg("App::cpanminus")
                .stdin(child.stdout.unwrap())
                .status()
        });

    println!("Perl {} installed successfully.", version);
    println!("Run: pun use {}", version);

    let _ = fs::remove_dir_all(&temp_dir);

    Ok(())
}

pub fn use_perl(version: &str) {
    let perl_path = get_perl_path(version);

    if !perl_path.exists() {
        println!("Perl {} is not installed.", version);
        println!("Run: pun install {}", version);
        return;
    }

    let bin_path = perl_path.join("bin");

    println!("To use Perl {}, run:", version);
    println!();
    println!("  export PATH=\"{}:$PATH\"", bin_path.display());
    println!();
    println!("Or add to your shell profile:");
    println!(
        "  echo 'export PATH=\"{}:$PATH\"' >> ~/.bashrc",
        bin_path.display()
    );
}

pub fn list_perls() {
    let perls_dir = get_perls_dir();

    if !perls_dir.exists() {
        println!("No Perl versions installed.");
        println!("Run: pun install <version>");
        return;
    }

    println!("Installed Perl versions:");

    if let Ok(entries) = fs::read_dir(&perls_dir) {
        for entry in entries.flatten() {
            if let Ok(meta) = entry.metadata() {
                if meta.is_dir() {
                    let version = entry.file_name().to_string_lossy().to_string();
                    let perl_bin = entry.path().join("bin").join("perl");

                    if perl_bin.exists() {
                        println!("  {}", version);
                    }
                }
            }
        }
    }
}

pub fn detect_perl_version(perl_bin: &Path) -> Result<String, String> {
    let output = Command::new(perl_bin)
        .arg("-e")
        .arg("print $^V")
        .output()
        .map_err(|e| e.to_string())?;

    if !output.status.success() {
        return Err("Failed to detect Perl version".to_string());
    }

    let mut version = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if version.starts_with('v') {
        version.remove(0);
    }
    Ok(version)
}

pub fn use_external_perl(perl_path_str: &str) {
    let mut perl_path = PathBuf::from(perl_path_str);

    // Expand tilde
    if perl_path.starts_with("~") {
        if let Ok(home) = env::var("HOME") {
            perl_path = PathBuf::from(home).join(perl_path.strip_prefix("~").unwrap());
        }
    }

    // Make absolute
    if !perl_path.is_absolute() {
        if let Ok(cwd) = env::current_dir() {
            perl_path = cwd.join(perl_path);
        }
    }

    if !perl_path.exists() {
        println!("Error: Path does not exist: {}", perl_path.display());
        return;
    }

    let (perl_bin, install_path) = if perl_path.is_file() {
        (
            perl_path.clone(),
            perl_path.parent().unwrap().parent().unwrap().to_path_buf(),
        )
    } else if perl_path.is_dir() {
        let bin_dir = perl_path.join("bin");
        if bin_dir.exists() && bin_dir.join("perl").exists() {
            (bin_dir.join("perl"), perl_path.clone())
        } else {
            let perl_bin = perl_path.join("bin").join("perl");
            (perl_bin, perl_path.clone())
        }
    } else {
        println!("Error: Invalid path: {}", perl_path.display());
        return;
    };

    if !perl_bin.exists() {
        println!("Error: Perl binary not found at: {}", perl_bin.display());
        return;
    }

    println!("Detecting Perl version...");
    let detected_version = match detect_perl_version(&perl_bin) {
        Ok(v) => {
            println!("Detected Perl version: {}", v);
            v
        }
        Err(e) => {
            println!("Warning: Could not detect Perl version: {}", e);
            "unknown".to_string()
        }
    };

    if Path::new(PROJECT_CONFIG).exists() {
        if let Ok((current_version, _)) = read_punrc() {
            if let Some(cv) = current_version {
                if cv != detected_version {
                    println!();
                    println!("Current .punrc specifies Perl version: {}", cv);
                    println!("Detected version from path: {}", detected_version);
                    print!("Update .punrc with detected version? (Y/n): ");
                    use std::io::{self, Write};
                    io::stdout().flush().unwrap();

                    let mut response = String::new();
                    io::stdin().read_line(&mut response).unwrap();
                    let response = response.trim().to_lowercase();

                    if response.is_empty() || response == "y" || response == "yes" {
                        update_punrc_version(&detected_version).unwrap();
                        println!("Updated .punrc with version: {}", detected_version);
                    }
                }
            }
        }
    }

    // Write .punlrc
    if let Ok(mut f) = std::fs::File::create(PROJECT_LOCAL_CONFIG) {
        use std::io::Write;
        writeln!(f, "perl-path = {}", install_path.display()).unwrap();
    }

    println!();
    println!(
        "Created {} pointing to: {}",
        PROJECT_LOCAL_CONFIG,
        install_path.display()
    );

    // Import and call activate_project
    crate::projects::activate_project();
}

pub fn show_env() {
    if !Path::new(PROJECT_CONFIG).exists() {
        return;
    }

    let mut perl_version: Option<String> = None;
    let mut perl_path: Option<String> = None;
    let mut local_lib = "lib".to_string();

    if Path::new(PROJECT_LOCAL_CONFIG).exists() {
        if let Ok((path, lib)) = read_punlrc() {
            perl_path = path;
            if let Some(l) = lib {
                local_lib = l;
            }
        }
    }

    if Path::new(PROJECT_CONFIG).exists() {
        if let Ok((version, lib)) = read_punrc() {
            perl_version = version;
            if let Some(l) = lib {
                local_lib = l;
            }
        }
    }

    if let Some(path) = perl_path {
        let path_buf = PathBuf::from(path);
        if path_buf.exists() {
            let bin_path = path_buf.join("bin");
            println!("export PATH=\"{}:$PATH\";", bin_path.display());
        }
    } else if let Some(version) = perl_version {
        let managed_path = get_perl_path(&version);
        if managed_path.exists() {
            let bin_path = managed_path.join("bin");
            println!("export PATH=\"{}:$PATH\";", bin_path.display());
        }
    }

    let abs_lib_path = std::env::current_dir()
        .unwrap_or_else(|_| PathBuf::from("."))
        .join(&local_lib)
        .canonicalize()
        .unwrap_or_else(|_| PathBuf::from(&local_lib));

    println!("export PERL5LIB=\"{}:$PERL5LIB\";", abs_lib_path.display());
}
