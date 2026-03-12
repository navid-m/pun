//! Git-related utilities
//!
//! GPL-3.0 - Navid M (C) 2026

use std::fs::File;
use std::io::Write;

pub fn generate_gitignore() -> std::io::Result<()> {
    let mut f = File::create(".gitignore")?;
    writeln!(f, "lib/")?;
    writeln!(f, ".punlrc")?;
    writeln!(f, "*.o")?;
    writeln!(f, "*.so")?;
    writeln!(f, "*.bs")?;
    writeln!(f, "*.swp")?;
    writeln!(f, "*~")?;
    writeln!(f, "blib/")?;
    writeln!(f, "_build/")?;
    writeln!(f, "cover_db/")?;
    writeln!(f, "Build")?;
    writeln!(f, "Build.bat")?;
    writeln!(f, "MYMETA.*")?;
    writeln!(f, "Makefile")?;
    writeln!(f, "Makefile.old")?;
    writeln!(f, "pm_to_blib")?;
    Ok(())
}
