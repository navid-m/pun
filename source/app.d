import std.stdio;
import std.getopt;
import std.file;
import std.path;
import std.process;
import std.string;
import std.algorithm;
import std.array;
import std.conv;

static immutable string PUN_HOME = ".pun";
static immutable string PERLS_DIR = "perls";
static immutable string PROJECT_CONFIG = ".punrc";
static immutable string PROJECT_LOCAL_CONFIG = ".punlrc";
static immutable string PROJECT_LOCK = "pun.lock";

void main(string[] args)
{
    if (args.length < 2)
    {
        printUsage();
        return;
    }

    string command = args[1];

    try
    {
        switch (command)
        {
        case "install":
            if (args.length < 3)
            {
                writeln("Usage: pun install <version>");
                return;
            }
            installPerl(args[2]);
            break;

        case "use":
            if (args.length < 3)
            {
                writeln("Usage: pun use <version>");
                return;
            }
            usePerl(args[2]);
            break;

        case "with":
            if (args.length < 3)
            {
                writeln("Usage: pun with <path>");
                return;
            }
            useExternalPerl(args[2]);
            break;

        case "list":
            listPerls();
            break;

        case "activate":
            activateProject();
            break;

        case "add":
            if (args.length < 3)
            {
                writeln("Usage: pun add <module>");
                return;
            }
            addModule(args[2]);
            break;

        case "init":
            bool isLib = args.canFind("--lib");
            string version_ = null;
            foreach (arg; args[2 .. $])
            {
                if (arg != "--lib")
                {
                    version_ = arg;
                    break;
                }
            }
            initProject(version_, isLib);
            break;

        case "env":
            showEnv();
            break;

        case "version":
            showVersion();
            break;

        default:
            writeln("Unknown command: ", command);
            printUsage();
        }
    }
    catch (Exception e)
    {
        stderr.writeln("Error: ", e.msg);
    }
}

void printUsage()
{
    writeln("usage: pun <options>");
    writeln;
    writeln("  install <version>       Install a Perl version");
    writeln("  use <version>           Switch to a Perl version");
    writeln("  with <path>             Use external Perl installation");
    writeln("  list                    List installed Perl versions");
    writeln("  init [version] [--lib]  Initialize project (--lib for library scaffold)");
    writeln("  activate                Activate project environment");
    writeln("  add <module>            Add a CPAN module to project");
    writeln("  env                     Show environment setup commands");
    writeln("  version                 Show pun version and exit");
}

string getPunHome() => buildPath(environment.get("HOME"), PUN_HOME);

string getPerlsDir() => buildPath(getPunHome(), PERLS_DIR);

string getPerlPath(string version_) => buildPath(getPerlsDir(), version_);

void showVersion()
{
    writeln("v0.0.1");
}

void ensurePunHome()
{
    string punHome = getPunHome();
    if (!exists(punHome))
    {
        mkdirRecurse(punHome);
    }

    string perlsDir = getPerlsDir();
    if (!exists(perlsDir))
    {
        mkdirRecurse(perlsDir);
    }
}

void installPerl(string version_)
{
    ensurePunHome();

    string perlPath = getPerlPath(version_);

    if (exists(perlPath))
    {
        writeln("Perl ", version_, " is already installed at ", perlPath);
        return;
    }

    writeln("Installing Perl ", version_, "...");
    writeln("This will download and compile Perl from source.");

    string tempDir = buildPath(tempDir(), "pun-build-" ~ version_);
    if (exists(tempDir))
    {
        rmdirRecurse(tempDir);
    }
    mkdirRecurse(tempDir);

    scope (exit)
    {
        if (exists(tempDir))
        {
            rmdirRecurse(tempDir);
        }
    }

    string tarball = "perl-" ~ version_ ~ ".tar.gz";
    string url = "https://www.cpan.org/src/5.0/" ~ tarball;

    writeln("Downloading from ", url);
    auto downloadResult = execute([
        "curl", "-L", "-o", buildPath(tempDir, tarball), url
    ]);
    if (downloadResult.status != 0)
    {
        throw new Exception("Failed to download Perl " ~ version_);
    }

    writeln("Extracting...");
    auto extractResult = execute(["tar", "-xzf", tarball], null, Config.none, size_t.max, tempDir);
    if (extractResult.status != 0)
    {
        throw new Exception("Failed to extract Perl tarball");
    }

    string buildDir = buildPath(tempDir, "perl-" ~ version_);
    writeln("Configuring...");

    auto configResult = execute(
        ["sh", "Configure", "-des", "-Dprefix=" ~ perlPath],
        null, Config.none, size_t.max, buildDir
    );

    if (configResult.status != 0)
    {
        throw new Exception("Failed to configure Perl");
    }

    writeln("Building (this may take a while)...");
    auto makeResult = execute(["make", "-j4"], null, Config.none, size_t.max, buildDir);
    if (makeResult.status != 0)
    {
        throw new Exception("Failed to build Perl");
    }

    writeln("Installing...");
    auto installResult = execute(["make", "install"], null, Config.none, size_t.max, buildDir);
    if (installResult.status != 0)
    {
        throw new Exception("Failed to install Perl");
    }

    writeln("Installing cpanm...");
    string perlBin = buildPath(perlPath, "bin", "perl");
    auto _ = execute([
        "curl", "-L", "https://cpanmin.us", "|", perlBin, "-", "App::cpanminus"
    ]);

    writeln("Perl ", version_, " installed successfully.");
    writeln("Run: pun use ", version_);
}

void usePerl(string version_)
{
    string perlPath = getPerlPath(version_);

    if (!exists(perlPath))
    {
        writeln("Perl ", version_, " is not installed.");
        writeln("Run: pun install ", version_);
        return;
    }

    string binPath = buildPath(perlPath, "bin");

    writeln("To use Perl ", version_, ", run:");
    writeln();
    writeln("  export PATH=\"", binPath, ":$PATH\"");
    writeln();
    writeln("Or add to your shell profile:");
    writeln("  echo 'export PATH=\"", binPath, ":$PATH\"' >> ~/.bashrc");
}

void listPerls()
{
    string perlsDir = getPerlsDir();

    if (!exists(perlsDir))
    {
        writeln("No Perl versions installed.");
        writeln("Run: pun install <version>");
        return;
    }

    writeln("Installed Perl versions:");

    foreach (entry; dirEntries(perlsDir, SpanMode.shallow))
    {
        if (entry.isDir)
        {
            string version_ = baseName(entry.name);
            string perlBin = buildPath(entry.name, "bin", "perl");

            if (exists(perlBin))
            {
                writeln("  ", version_);
            }
        }
    }
}

string detectPerlVersion(string perlBin)
{
    auto result = execute([perlBin, "-e", "print $^V"]);
    if (result.status != 0)
    {
        throw new Exception("Failed to detect Perl version");
    }
    string output = strip(result.output);
    if (output.startsWith("v"))
    {
        output = output[1 .. $];
    }
    return output;
}

void useExternalPerl(string perlPath)
{
    if (perlPath.startsWith("~"))
    {
        perlPath = expandTilde(perlPath);
    }

    perlPath = absolutePath(perlPath);

    if (!exists(perlPath))
    {
        writeln("Error: Path does not exist: ", perlPath);
        return;
    }

    string perlBin;
    string installPath;

    if (isFile(perlPath))
    {
        perlBin = perlPath;
        installPath = dirName(dirName(perlPath));
    }
    else if (isDir(perlPath))
    {
        if (baseName(perlPath) == "bin" && exists(buildPath(perlPath, "perl")))
        {
            perlBin = buildPath(perlPath, "perl");
            installPath = dirName(perlPath);
        }
        else
        {
            perlBin = buildPath(perlPath, "bin", "perl");
            installPath = perlPath;
        }
    }
    else
    {
        writeln("Error: Invalid path: ", perlPath);
        return;
    }

    if (!exists(perlBin))
    {
        writeln("Error: Perl binary not found at: ", perlBin);
        return;
    }

    writeln("Detecting Perl version...");
    string detectedVersion;
    try
    {
        detectedVersion = detectPerlVersion(perlBin);
        writeln("Detected Perl version: ", detectedVersion);
    }
    catch (Exception e)
    {
        writeln("Warning: Could not detect Perl version: ", e.msg);
        detectedVersion = "unknown";
    }

    if (exists(PROJECT_CONFIG))
    {
        string currentVersion = null;

        foreach (line; File(PROJECT_CONFIG).byLine())
        {
            string l = strip(line.idup);
            if (l.startsWith("perl"))
            {
                auto parts = l.split("=");
                if (parts.length == 2)
                {
                    currentVersion = strip(parts[1]);
                }
            }
        }

        if (currentVersion && currentVersion != detectedVersion)
        {
            writeln;
            writeln("Current .punrc specifies Perl version: ", currentVersion);
            writeln("Detected version from path: ", detectedVersion);
            write("Update .punrc with detected version? (Y/n): ");
            stdout.flush();

            string response = strip(readln());
            if (response == "" || response.toLower() == "y" || response.toLower() == "yes")
            {
                updatePunrcVersion(detectedVersion);
                writeln("Updated .punrc with version: ", detectedVersion);
            }
        }
    }

    auto f = File(PROJECT_LOCAL_CONFIG, "w");
    f.writeln("perl-path = ", installPath);
    f.close();

    writeln();
    writeln("Created ", PROJECT_LOCAL_CONFIG, " pointing to: ", installPath);
    writeln("Run: pun activate");
}

void updatePunrcVersion(string version_)
{
    if (!exists(PROJECT_CONFIG))
    {
        return;
    }

    string[] lines;
    bool foundPerl = false;

    foreach (line; File(PROJECT_CONFIG).byLine())
    {
        string l = line.idup;
        if (strip(l).startsWith("perl"))
        {
            lines ~= "perl = " ~ version_;
            foundPerl = true;
        }
        else
        {
            lines ~= l;
        }
    }

    if (!foundPerl)
    {
        lines = ["perl = " ~ version_] ~ lines;
    }

    auto f = File(PROJECT_CONFIG, "w");
    foreach (line; lines)
    {
        f.writeln(line);
    }
    f.close();
}

void initProject(string version_, bool isLib)
{
    if (exists(PROJECT_CONFIG))
    {
        writeln("Project already initialized (.punrc exists)");
        return;
    }

    string libDir = "lib";
    if (!exists(libDir))
    {
        mkdirRecurse(libDir);
    }

    auto f = File(PROJECT_CONFIG, "w");
    if (version_)
    {
        f.writeln("perl = ", version_);
    }
    f.writeln("local-lib = lib");
    f.close();

    if (!exists(".gitignore"))
    {
        generateGitignore();
        writeln("Generated .gitignore");
    }
    else
    {
        writeln("Skipped .gitignore (already exists)");
    }

    if (isLib)
    {
        generateLibScaffolding();
    }
    else
    {
        generateHelloWorld();
    }

    writeln("Project initialized");
    if (version_)
    {
        writeln("  Perl version: ", version_);
    }
    writeln("  Local lib: lib/");
    writeln();
    writeln("Run: pun activate");
}

void generateHelloWorld()
{
    if (exists("main.pl"))
    {
        writeln("Skipped main.pl (already exists)");
        return;
    }

    auto f = File("main.pl", "w");
    f.writeln("#!/usr/bin/env perl");
    f.writeln("use strict;");
    f.writeln("use warnings;");
    f.writeln();
    f.writeln("print \"Hello, World!\\n\";");
    f.close();

    version (Posix)
    {
        import core.sys.posix.sys.stat;

        chmod("main.pl".toStringz(), S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH);
    }

    writeln("Generated main.pl");
}

void generateLibScaffolding()
{
    string projectName = baseName(getcwd());
    string moduleName = projectName[0 .. 1].toUpper() ~ projectName[1 .. $];
    string moduleFile = buildPath("lib", moduleName ~ ".pm");

    if (exists(moduleFile))
    {
        writeln("Skipped ", moduleFile, " (already exists)");
    }
    else
    {
        auto f = File(moduleFile, "w");
        f.writeln("package ", moduleName, ";");
        f.writeln();
        f.writeln("use strict;");
        f.writeln("use warnings;");
        f.writeln();
        f.writeln("our $VERSION = '0.01';");
        f.writeln();
        f.writeln("sub new {");
        f.writeln("    my ($class) = @_;");
        f.writeln("    return bless {}, $class;");
        f.writeln("}");
        f.writeln();
        f.writeln("1;");
        f.writeln();
        f.writeln("__END__");
        f.writeln();
        f.writeln("=head1 NAME");
        f.writeln();
        f.writeln(moduleName, " - A Perl module");
        f.writeln();
        f.writeln("=head1 SYNOPSIS");
        f.writeln();
        f.writeln("    use ", moduleName, ";");
        f.writeln("    my $obj = ", moduleName, "->new();");
        f.writeln();
        f.writeln("=head1 DESCRIPTION");
        f.writeln();
        f.writeln("This module provides...");
        f.writeln();
        f.writeln("=cut");
        f.close();
        writeln("Generated ", moduleFile);
    }

    string testFile = "test.pl";
    if (exists(testFile))
    {
        writeln("Skipped ", testFile, " (already exists)");
    }
    else
    {
        auto f = File(testFile, "w");
        f.writeln("#!/usr/bin/env perl");
        f.writeln("use strict;");
        f.writeln("use warnings;");
        f.writeln("use lib 'lib';");
        f.writeln("use ", moduleName, ";");
        f.writeln();
        f.writeln("my $obj = ", moduleName, "->new();");
        f.writeln("print \"Module loaded successfully\\n\";");
        f.close();

        version (Posix)
        {
            import core.sys.posix.sys.stat;

            chmod(testFile.toStringz(), S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH);
        }

        writeln("Generated ", testFile);
    }
}

void generateGitignore()
{
    auto f = File(".gitignore", "w");
    f.writeln("lib/");
    f.writeln(".punlrc");
    f.writeln("*.o");
    f.writeln("*.so");
    f.writeln("*.bs");
    f.writeln("*.swp");
    f.writeln("*~");
    f.writeln("blib/");
    f.writeln("_build/");
    f.writeln("cover_db/");
    f.writeln("Build");
    f.writeln("Build.bat");
    f.writeln("MYMETA.*");
    f.writeln("Makefile");
    f.writeln("Makefile.old");
    f.writeln("pm_to_blib");
    f.close();
}

void activateProject()
{
    if (!exists(PROJECT_CONFIG))
    {
        writeln("No .punrc found. Run: pun init");
        return;
    }

    string perlVersion = null;
    string perlPath = null;
    string localLib = "lib";

    if (exists(PROJECT_LOCAL_CONFIG))
    {
        foreach (line; File(PROJECT_LOCAL_CONFIG).byLine())
        {
            string l = strip(line.idup);
            if (l.startsWith("perl-path"))
            {
                auto parts = l.split("=");
                if (parts.length == 2)
                {
                    perlPath = strip(parts[1]);
                }
            }
        }
    }

    foreach (line; File(PROJECT_CONFIG).byLine())
    {
        string l = strip(line.idup);
        if (l.startsWith("perl"))
        {
            auto parts = l.split("=");
            if (parts.length == 2)
            {
                perlVersion = strip(parts[1]);
            }
        }
        else if (l.startsWith("local-lib"))
        {
            auto parts = l.split("=");
            if (parts.length == 2)
            {
                localLib = strip(parts[1]);
            }
        }
    }

    writeln("Activating project environment...");
    writeln();
    writeln("Run these commands:");
    writeln();

    if (perlPath)
    {
        if (!exists(perlPath))
        {
            writeln("# Warning: Perl path not found: ", perlPath);
        }
        else
        {
            string binPath = buildPath(perlPath, "bin");
            writeln("export PATH=\"", binPath, ":$PATH\"");
        }
    }
    else if (perlVersion)
    {
        string managedPath = getPerlPath(perlVersion);
        if (!exists(managedPath))
        {
            writeln("# Warning: Perl ", perlVersion, " not installed");
            writeln("# Run: pun install ", perlVersion);
        }
        else
        {
            string binPath = buildPath(managedPath, "bin");
            writeln("export PATH=\"", binPath, ":$PATH\"");
        }
    }

    string absLibPath = absolutePath(localLib);
    writeln("export PERL5LIB=\"", absLibPath, ":$PERL5LIB\"");
    writeln();
    writeln("Or source this:");
    writeln("  eval \"$(pun env)\"");
}

void ensureCpanm()
{
    version (Windows)
    {
        throw new Exception("cpanm not found. Install App::cpanminus manually.");
    }
    else
    {
        writeln("cpanm not found. Installing via system package manager...");

        auto result = execute(["which", "apt-get"]);
        if (result.status == 0)
        {
            execute(["sudo", "apt-get", "install", "-y", "cpanminus"]);
            return;
        }

        result = execute(["which", "dnf"]);
        if (result.status == 0)
        {
            execute(["sudo", "dnf", "install", "-y", "perl-App-cpanminus"]);
            return;
        }

        result = execute(["which", "yum"]);
        if (result.status == 0)
        {
            execute(["sudo", "yum", "install", "-y", "perl-App-cpanminus"]);
            return;
        }

        result = execute(["which", "pacman"]);
        if (result.status == 0)
        {
            execute([
                "sudo", "pacman", "-S", "--noconfirm", "perl-app-cpanminus"
            ]);
            return;
        }

        result = execute(["which", "zypper"]);
        if (result.status == 0)
        {
            execute(["sudo", "zypper", "install", "-y", "perl-App-cpanminus"]);
            return;
        }

        result = execute(["which", "brew"]);
        if (result.status == 0)
        {
            execute(["brew", "install", "cpanminus"]);
            return;
        }

        throw new Exception("Could not detect package manager. Install cpanminus manually.");
    }
}

void addModule(string moduleName)
{
    if (!exists(PROJECT_CONFIG))
    {
        writeln("No .punrc found. Run: pun init");
        return;
    }

    auto cpanmCheck = execute(["which", "cpanm"]);
    if (cpanmCheck.status != 0)
    {
        ensureCpanm();
    }

    string localLib = "lib";

    foreach (line; File(PROJECT_CONFIG).byLine())
    {
        string l = strip(line.idup);
        if (l.startsWith("local-lib"))
        {
            auto parts = l.split("=");
            if (parts.length == 2)
            {
                localLib = strip(parts[1]);
            }
        }
    }

    if (!exists(localLib))
    {
        mkdirRecurse(localLib);
    }

    writeln("Installing ", moduleName, " to ", localLib, "...");

    auto result = execute([
        "cpanm",
        "--local-lib=" ~ localLib,
        moduleName
    ]);

    if (result.status == 0)
    {
        writeln(moduleName, " installed");
        auto lockFile = File(PROJECT_LOCK, "a");
        lockFile.writeln(moduleName);
        lockFile.close();
    }
    else
    {
        writeln("Failed to install ", moduleName);
        writeln(result.output);
    }
}

void showEnv()
{
    if (!exists(PROJECT_CONFIG))
    {
        return;
    }

    string perlVersion = null;
    string perlPath = null;
    string localLib = "lib";

    if (exists(PROJECT_LOCAL_CONFIG))
    {
        foreach (line; File(PROJECT_LOCAL_CONFIG).byLine())
        {
            string l = strip(line.idup);
            if (l.startsWith("perl-path"))
            {
                auto parts = l.split("=");
                if (parts.length == 2)
                {
                    perlPath = strip(parts[1]);
                }
            }
        }
    }

    foreach (line; File(PROJECT_CONFIG).byLine())
    {
        string l = strip(line.idup);
        if (l.startsWith("perl"))
        {
            auto parts = l.split("=");
            if (parts.length == 2)
            {
                perlVersion = strip(parts[1]);
            }
        }
        else if (l.startsWith("local-lib"))
        {
            auto parts = l.split("=");
            if (parts.length == 2)
            {
                localLib = strip(parts[1]);
            }
        }
    }

    if (perlPath)
    {
        if (exists(perlPath))
        {
            string binPath = buildPath(perlPath, "bin");
            writeln("export PATH=\"", binPath, ":$PATH\";");
        }
    }
    else if (perlVersion)
    {
        string managedPath = getPerlPath(perlVersion);
        if (exists(managedPath))
        {
            string binPath = buildPath(managedPath, "bin");
            writeln("export PATH=\"", binPath, ":$PATH\";");
        }
    }

    string absLibPath = absolutePath(localLib);
    writeln("export PERL5LIB=\"", absLibPath, ":$PERL5LIB\";");
}
