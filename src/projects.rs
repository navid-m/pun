//! Project management functions
//!
//! GPL-3.0 - Navid M (C) 2026

use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::cpanm::install_module;
use crate::environment::get_perl_path;
use crate::git::generate_gitignore;
use crate::globs::{PROJECT_CONFIG, PROJECT_LOCAL_CONFIG, PROJECT_LOCK};

pub fn read_punrc() -> Result<(Option<String>, Option<String>), std::io::Error> {
    let mut perl_version: Option<String> = None;
    let mut local_lib: Option<String> = None;

    if !Path::new(PROJECT_CONFIG).exists() {
        return Ok((perl_version, local_lib));
    }

    let file = fs::File::open(PROJECT_CONFIG)?;
    let reader = BufReader::new(file);

    for line in reader.lines() {
        let line = line?;
        let trimmed = line.trim();

        if trimmed.starts_with("perl") {
            if let Some((_, value)) = trimmed.split_once('=') {
                perl_version = Some(value.trim().to_string());
            }
        } else if trimmed.starts_with("local-lib") {
            if let Some((_, value)) = trimmed.split_once('=') {
                local_lib = Some(value.trim().to_string());
            }
        }
    }

    Ok((perl_version, local_lib))
}

pub fn read_punlrc() -> Result<(Option<String>, Option<String>), std::io::Error> {
    let mut perl_path: Option<String> = None;
    let mut local_lib: Option<String> = None;

    if !Path::new(PROJECT_LOCAL_CONFIG).exists() {
        return Ok((perl_path, local_lib));
    }

    let file = fs::File::open(PROJECT_LOCAL_CONFIG)?;
    let reader = BufReader::new(file);

    for line in reader.lines() {
        let line = line?;
        let trimmed = line.trim();

        if trimmed.starts_with("perl-path") {
            if let Some((_, value)) = trimmed.split_once('=') {
                perl_path = Some(value.trim().to_string());
            }
        } else if trimmed.starts_with("local-lib") {
            if let Some((_, value)) = trimmed.split_once('=') {
                local_lib = Some(value.trim().to_string());
            }
        }
    }

    Ok((perl_path, local_lib))
}

pub fn update_punrc_version(version: &str) -> std::io::Result<()> {
    if !Path::new(PROJECT_CONFIG).exists() {
        return Ok(());
    }

    let mut lines: Vec<String> = Vec::new();
    let mut found_perl = false;

    let file = fs::File::open(PROJECT_CONFIG)?;
    let reader = BufReader::new(file);

    for line in reader.lines() {
        let line = line?;
        let trimmed = line.trim();

        if trimmed.starts_with("perl") {
            lines.push(format!("perl = {}", version));
            found_perl = true;
        } else {
            lines.push(line);
        }
    }

    if !found_perl {
        lines.insert(0, format!("perl = {}", version));
    }

    let mut f = fs::File::create(PROJECT_CONFIG)?;
    for line in lines {
        writeln!(f, "{}", line)?;
    }

    Ok(())
}

pub fn init_project(version: Option<&str>, is_lib: bool) {
    if Path::new(PROJECT_CONFIG).exists() {
        println!("Project already initialized (.punrc exists)");
        return;
    }

    let lib_dir = "lib";
    if !Path::new(lib_dir).exists() {
        fs::create_dir_all(lib_dir).unwrap();
    }

    {
        let mut f = fs::File::create(PROJECT_CONFIG).unwrap();
        if let Some(v) = version {
            writeln!(f, "perl = {}", v).unwrap();
        }
        writeln!(f, "local-lib = lib").unwrap();
    }

    if !Path::new(".gitignore").exists() {
        generate_gitignore().unwrap();
        println!("Generated .gitignore");
    } else {
        println!("Skipped .gitignore (already exists)");
    }

    if is_lib {
        generate_lib_scaffolding();
    } else {
        generate_hello_world();
    }

    println!("Project initialized");
    if let Some(v) = version {
        println!("  Perl version: {}", v);
    }
    println!("  Local lib: lib/");
    println!();
    activate_project();
}

fn generate_hello_world() {
    if Path::new("main.pl").exists() {
        println!("Skipped main.pl (already exists)");
        return;
    }

    let mut f = fs::File::create("main.pl").unwrap();
    writeln!(f, "#!/usr/bin/env perl").unwrap();
    writeln!(f, "use strict;").unwrap();
    writeln!(f, "use warnings;").unwrap();
    writeln!(f).unwrap();
    writeln!(f, "print \"Hello, World!\\n\";").unwrap();

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions("main.pl", fs::Permissions::from_mode(0o755)).unwrap();
    }

    println!("Generated main.pl");
}

fn generate_lib_scaffolding() {
    let project_name = env::current_dir()
        .unwrap()
        .file_name()
        .unwrap()
        .to_string_lossy()
        .to_string();

    let module_name = if project_name.is_empty() {
        "MyModule".to_string()
    } else {
        let mut chars = project_name.chars();
        match chars.next() {
            None => "MyModule".to_string(),
            Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        }
    };

    let module_file = PathBuf::from("lib").join(format!("{}.pm", module_name));

    if module_file.exists() {
        println!("Skipped {} (already exists)", module_file.display());
    } else {
        let mut f = fs::File::create(&module_file).unwrap();
        writeln!(f, "package {};", module_name).unwrap();
        writeln!(f).unwrap();
        writeln!(f, "use strict;").unwrap();
        writeln!(f, "use warnings;").unwrap();
        writeln!(f).unwrap();
        writeln!(f, "our $VERSION = '0.01';").unwrap();
        writeln!(f).unwrap();
        writeln!(f, "sub new {{").unwrap();
        writeln!(f, "    my ($class) = @_;").unwrap();
        writeln!(f, "    return bless {{}}, $class;").unwrap();
        writeln!(f, "}}").unwrap();
        writeln!(f).unwrap();
        writeln!(f, "1;").unwrap();
        writeln!(f).unwrap();
        writeln!(f, "__END__").unwrap();
        writeln!(f).unwrap();
        writeln!(f, "=head1 NAME").unwrap();
        writeln!(f).unwrap();
        writeln!(f, "{} - A Perl module", module_name).unwrap();
        writeln!(f).unwrap();
        writeln!(f, "=head1 SYNOPSIS").unwrap();
        writeln!(f).unwrap();
        writeln!(f, "    use {};", module_name).unwrap();
        writeln!(f, "    my $obj = {}->new();", module_name).unwrap();
        writeln!(f).unwrap();
        writeln!(f, "=head1 DESCRIPTION").unwrap();
        writeln!(f).unwrap();
        writeln!(f, "This module provides...").unwrap();
        writeln!(f).unwrap();
        writeln!(f, "=cut").unwrap();

        println!("Generated {}", module_file.display());
    }

    let test_file = "test.pl";
    if Path::new(test_file).exists() {
        println!("Skipped {} (already exists)", test_file);
    } else {
        let mut f = fs::File::create(test_file).unwrap();
        writeln!(f, "#!/usr/bin/env perl").unwrap();
        writeln!(f, "use strict;").unwrap();
        writeln!(f, "use warnings;").unwrap();
        writeln!(f, "use lib 'lib';").unwrap();
        writeln!(f, "use {};", module_name).unwrap();
        writeln!(f).unwrap();
        writeln!(f, "my $obj = {}->new();", module_name).unwrap();
        writeln!(f, "print \"Module loaded successfully\\n\";").unwrap();

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(test_file, fs::Permissions::from_mode(0o755)).unwrap();
        }

        println!("Generated {}", test_file);
    }
}

pub fn activate_project() {
    if !Path::new(PROJECT_CONFIG).exists() {
        println!("No .punrc found. Run: pun init");
        return;
    }

    let (perl_version, local_lib) = read_punrc().unwrap();
    let (perl_path, _) = read_punlrc().unwrap();

    println!("Activating project environment...");
    println!();
    println!("Run these commands:");
    println!();

    if let Some(path) = perl_path {
        let path_buf = PathBuf::from(path);
        if !path_buf.exists() {
            println!("# Warning: Perl path not found: {}", path_buf.display());
        } else {
            let bin_path = path_buf.join("bin");
            println!("export PATH=\"{}:$PATH\"", bin_path.display());
        }
    } else if let Some(version) = perl_version {
        let managed_path = get_perl_path(&version);
        if !managed_path.exists() {
            println!("# Warning: Perl {} not installed", version);
            println!("# Run: pun install {}", version);
        } else {
            let bin_path = managed_path.join("bin");
            println!("export PATH=\"{}:$PATH\"", bin_path.display());
        }
    }

    let lib_path = local_lib.unwrap_or_else(|| "lib".to_string());
    let abs_lib_path = env::current_dir()
        .unwrap_or_else(|_| PathBuf::from("."))
        .join(&lib_path)
        .canonicalize()
        .unwrap_or_else(|_| PathBuf::from(&lib_path));

    println!("export PERL5LIB=\"{}:$PERL5LIB\"", abs_lib_path.display());
    println!();
    println!("Or source this:");
    println!("  eval \"$(pun env)\"");
}

pub fn restore_modules() {
    if !Path::new(PROJECT_CONFIG).exists() {
        println!("No .punrc found. Run: pun init");
        return;
    }

    if !Path::new(PROJECT_LOCK).exists() {
        println!("No {} found. Nothing to restore.", PROJECT_LOCK);
        return;
    }

    let (_, local_lib) = read_punrc().unwrap();
    let local_lib = local_lib.unwrap_or_else(|| "lib".to_string());

    if !Path::new(&local_lib).exists() {
        fs::create_dir_all(&local_lib).unwrap();
    }

    println!("Restoring modules from {}...", PROJECT_LOCK);

    let file = fs::File::open(PROJECT_LOCK).unwrap();
    let reader = BufReader::new(file);

    for line in reader.lines() {
        let line = line.unwrap();
        let l = line.trim();

        if l.is_empty() || l.starts_with('#') {
            continue;
        }

        let parts: Vec<&str> = l.split("==").collect();
        let module_spec: String;

        if parts.len() == 2 {
            let module_name = parts[0].trim();
            let version = parts[1].trim();

            if version == "unknown" {
                module_spec = module_name.to_string();
            } else {
                module_spec = format!("{}@{}", module_name, version);
            }
        } else {
            module_spec = parts[0].trim().to_string();
        }

        println!("Installing {}...", module_spec);

        let local_lib_path = PathBuf::from(&local_lib);
        match install_module(&module_spec, &local_lib_path) {
            Ok(_) => println!("✓ {}", module_spec),
            Err(e) => eprintln!("✗ Failed to install {}: {}", module_spec, e),
        }
    }

    println!("Restore complete");
}

pub fn add_module(module_name: &str) {
    if !Path::new(PROJECT_CONFIG).exists() {
        println!("No .punrc found. Run: pun init");
        return;
    }

    let (_, local_lib) = read_punrc().unwrap();
    let local_lib = local_lib.unwrap_or_else(|| "lib".to_string());

    if !Path::new(&local_lib).exists() {
        fs::create_dir_all(&local_lib).unwrap();
    }

    println!("Installing {} to {}...", module_name, local_lib);

    let local_lib_path = PathBuf::from(&local_lib);
    match install_module(module_name, &local_lib_path) {
        Ok(version) => {
            println!("✓ {} installed", module_name);
            update_lock_file(module_name, &version).unwrap();
        }
        Err(e) => {
            eprintln!("✗ Failed to install {}: {}", module_name, e);
        }
    }
}

fn update_lock_file(module_name: &str, version: &str) -> std::io::Result<()> {
    let mut modules: std::collections::BTreeMap<String, String> = std::collections::BTreeMap::new();

    if Path::new(PROJECT_LOCK).exists() {
        let file = fs::File::open(PROJECT_LOCK)?;
        let reader = BufReader::new(file);

        for line in reader.lines() {
            let line = line?;
            let l = line.trim();

            if l.is_empty() || l.starts_with('#') {
                continue;
            }

            let parts: Vec<&str> = l.split("==").collect();
            if parts.len() == 2 {
                modules.insert(parts[0].trim().to_string(), parts[1].trim().to_string());
            } else if parts.len() == 1 {
                modules.insert(parts[0].trim().to_string(), "unknown".to_string());
            }
        }
    }

    modules.insert(module_name.to_string(), version.to_string());

    let mut f = fs::File::create(PROJECT_LOCK)?;
    writeln!(f, "# pun.lock")?;
    writeln!(f)?;

    for (mod_name, mod_version) in &modules {
        writeln!(f, "{}=={}", mod_name, mod_version)?;
    }

    println!("Updated {}", PROJECT_LOCK);
    Ok(())
}

pub fn run_script(args: &[String]) {
    if args.is_empty() {
        println!("Usage: pun run <file.pl> [args...]");
        return;
    }

    let script_file = &args[0];

    if !Path::new(script_file).exists() {
        println!("Error: File not found: {}", script_file);
        return;
    }

    let mut perl_bin = "perl".to_string();
    let mut local_lib = "lib".to_string();

    if Path::new(PROJECT_CONFIG).exists() {
        let (perl_version, lib) = read_punrc().unwrap();
        let (perl_path, _) = read_punlrc().unwrap();

        if let Some(path) = perl_path {
            let path_buf = PathBuf::from(path);
            if path_buf.exists() {
                perl_bin = path_buf
                    .join("bin")
                    .join("perl")
                    .to_string_lossy()
                    .to_string();
            }
        } else if let Some(version) = perl_version {
            let managed_path = get_perl_path(&version);
            if managed_path.exists() {
                perl_bin = managed_path
                    .join("bin")
                    .join("perl")
                    .to_string_lossy()
                    .to_string();
            }
        }

        if let Some(lib) = lib {
            local_lib = lib;
        }
    }

    let mut cmd = Command::new(&perl_bin);
    cmd.args(args);

    if Path::new(&local_lib).exists() {
        let abs_lib_path = env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(&local_lib)
            .canonicalize()
            .unwrap_or_else(|_| PathBuf::from(&local_lib));

        let current_perl5lib = env::var("PERL5LIB").unwrap_or_default();
        let new_perl5lib = if current_perl5lib.is_empty() {
            abs_lib_path.to_string_lossy().to_string()
        } else {
            format!("{}:{}", abs_lib_path.display(), current_perl5lib)
        };
        cmd.env("PERL5LIB", new_perl5lib);
    }

    let mut child = cmd.spawn().expect("Failed to run script");
    let _ = child.wait();
}
