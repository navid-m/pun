mod cpanm;
mod environment;
mod git;
mod globs;
mod projects;

use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_usage();
        return;
    }

    let command = &args[1];

    match command.as_str() {
        "install" => {
            if args.len() < 3 {
                println!("Usage: pun install <version>");
                return;
            }
            if let Err(e) = environment::install_perl(&args[2]) {
                eprintln!("Error: {}", e);
            }
        }

        "use" => {
            if args.len() < 3 {
                println!("Usage: pun use <version>");
                return;
            }
            environment::use_perl(&args[2]);
        }

        "with" => {
            if args.len() < 3 {
                println!("Usage: pun with <path>");
                return;
            }
            environment::use_external_perl(&args[2]);
        }

        "list" => {
            environment::list_perls();
        }

        "activate" => {
            projects::activate_project();
        }

        "add" => {
            if args.len() < 3 {
                println!("Usage: pun add <module>");
                return;
            }
            projects::add_module(&args[2]);
        }

        "restore" => {
            projects::restore_modules();
        }

        "init" => {
            let mut is_lib = false;
            let mut version: Option<&str> = None;

            for arg in args.iter().skip(2) {
                if arg == "--lib" {
                    is_lib = true;
                } else {
                    version = Some(arg);
                }
            }

            projects::init_project(version, is_lib);
        }

        "env" => {
            environment::show_env();
        }

        "run" => {
            if args.len() < 3 {
                println!("Usage: pun run <file.pl>");
                return;
            }
            projects::run_script(&args[2..]);
        }

        "version" => {
            environment::show_version();
        }

        _ => {
            println!("Unknown command: {}", command);
            print_usage();
        }
    }
}

fn print_usage() {
    println!("usage: pun <options>");
    println!();
    println!("  install <version>       Install a Perl version");
    println!("  use <version>           Switch to a Perl version");
    println!("  with <path>             Use external Perl installation");
    println!("  list                    List installed Perl versions");
    println!("  init [version] [--lib]  Initialize project (--lib for library scaffold)");
    println!("  activate                Activate project environment");
    println!("  add <module>            Add a CPAN module to project");
    println!("  restore                 Restore modules from pun.lock");
    println!("  run <file>              Run a Perl script with project environment");
    println!("  env                     Show environment setup commands");
    println!("  version                 Show pun version and exit");
}
