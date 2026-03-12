# pun

Perl version and package manager. 

## Installation from source

The Rust toolchain is required to build from source.

```bash
cargo build --release
sudo cp ./target/release/pun /usr/local/bin/
```


## Quick Start

Install a Perl version:

```bash
pun install 5.40.0
```

This downloads, compiles, and installs Perl to `~/.pun/perls/5.40.0/`

Use a Perl version globally:

```bash
pun use 5.40.0
```

This shows you the export command to add to your shell.

Initialize a project:

```bash
cd myproject
pun init 5.40.0
```

Creates `.punrc` and `lib/` directory for project-local modules. Also generates a `.gitignore` file if one doesn't exist.

Activate project environment:

```bash
pun activate
```

Shows commands to set up PATH and PERL5LIB. Or use:

```bash
eval "$(pun env)"
```

Add modules to your project:

```bash
pun add Mojolicious
pun add DBI
```

Modules install to `./lib/` and are tracked in `pun.lock`

Commands:

- `pun install <version>` - Download and install a Perl version
- `pun use <version>` - Show how to switch to a Perl version
- `pun with <path>` - Use an external Perl installation
- `pun list` - List installed Perl versions
- `pun init [version]` - Initialize project with optional Perl version
- `pun activate` - Show project activation commands
- `pun add <module>` - Install CPAN module to project
- `pun env` - Output environment variables (for eval)

Each Perl version is installed to `~/.pun/perls/<version>/` with its own `bin/`, `lib/`, etc.

When you activate a version, `pun` prepends that version's `bin/` to your `PATH`:

```bash
export PATH="$HOME/.pun/perls/5.40.0/bin:$PATH"
```

### Project Isolation

Each project has:
- `.punrc` - Configuration file specifying Perl version and local lib path
- `.punlrc` - Optional local configuration pointing to external Perl installation
- `lib/` - Local directory for project-specific modules
- `pun.lock` - List of installed modules

When activated, `PERL5LIB` points to the project's `lib/`:

```bash
export PERL5LIB="/path/to/project/lib:$PERL5LIB"
```

Perl searches this directory first when loading modules, so each project's dependencies are isolated.

### Using External Perl Installations

If you have an existing Perl installation (e.g., system Perl, perlbrew, or custom build), you can use it with your project:

```bash
pun with ~/perl5/perlbrew/perls/perl-5.42.0
```

This will:
1. Detect the Perl version from the provided path
2. Prompt to update `.punrc` if the version differs
3. Create `.punlrc` pointing to the external installation
4. Use the external Perl when you run `pun activate`

The `.punlrc` file takes precedence over `.punrc` for the Perl installation path, allowing you to override the managed version on a per-project basis.

## Example Workflow

```bash
pun install 5.40.0
mkdir myapp && cd myapp
pun init 5.40.0
eval "$(pun env)"
pun add Mojolicious
pun add DBD::SQLite
perl -MMojolicious -e 'print $Mojolicious::VERSION'
```

## Configuration File (.punrc)

```
perl = 5.40.0
local-lib = lib
```

## Local Configuration File (.punlrc)

Optional file created by `pun with` to point to an external Perl installation:

```
perl-path = /home/user/perl5/perlbrew/perls/perl-5.42.0
```

When `.punlrc` exists, it takes precedence over the `perl` setting in `.punrc`.

## License

GPL-3.0-only

Navid M (C) 2026
