module pun.projects;

import std.file;
import std.string;
import std.stdio;
import std.process;

import pun.globs;
import pun.environment;
import pun.git;
import pun.cpanm;

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
    activateProject();
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

import std.path;

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

void restoreModules()
{
    if (!exists(PROJECT_CONFIG))
    {
        writeln("No .punrc found. Run: pun init");
        return;
    }

    if (!exists(PROJECT_LOCK))
    {
        writeln("No ", PROJECT_LOCK, " found. Nothing to restore.");
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

    writeln("Restoring modules from ", PROJECT_LOCK, "...");

    foreach (line; File(PROJECT_LOCK).byLine())
    {
        string l = strip(line.idup);
        if (l.length == 0 || l.startsWith("#"))
            continue;

        string moduleSpec;
        auto parts = l.split("==");

        if (parts.length == 2)
        {
            string moduleName = strip(parts[0]);
            string version_ = strip(parts[1]);

            if (version_ == "unknown")
            {
                moduleSpec = moduleName;
            }
            else
            {
                moduleSpec = moduleName ~ "@" ~ version_;
            }
        }
        else
        {
            moduleSpec = strip(parts[0]);
        }

        writeln("Installing ", moduleSpec, "...");

        auto result = execute([
            "cpanm",
            "--local-lib=" ~ localLib,
            moduleSpec
        ]);

        if (result.status == 0)
        {
            writeln(moduleSpec);
        }
        else
        {
            stderr.writeln("Failed to install ", moduleSpec);
        }
    }

    writeln("Restore complete");
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

        string installedVersion = getInstalledModuleVersion(moduleName, localLib);
        updateLockFile(moduleName, installedVersion);
    }
    else
    {
        writeln("Failed to install ", moduleName);
        writeln(result.output);
    }
}

string getInstalledModuleVersion(string moduleName, string localLib)
{
    string moduleFile = moduleName.replace("::", "/") ~ ".pm";
    string searchPath = buildPath(absolutePath(localLib), "lib", "perl5");

    auto result = execute([
        "perl",
        "-I" ~ searchPath,
        "-M" ~ moduleName,
        "-e",
        "print $" ~ moduleName ~ "::VERSION || 'unknown'"
    ]);

    if (result.status == 0 && result.output.length > 0)
    {
        return strip(result.output);
    }

    return "unknown";
}

void updateLockFile(string moduleName, string version_)
{
    string[string] modules;

    if (exists(PROJECT_LOCK))
    {
        foreach (line; File(PROJECT_LOCK).byLine())
        {
            string l = strip(line.idup);
            if (l.length == 0 || l.startsWith("#"))
                continue;

            auto parts = l.split("==");
            if (parts.length == 2)
            {
                modules[strip(parts[0])] = strip(parts[1]);
            }
            else if (parts.length == 1)
            {
                modules[strip(parts[0])] = "unknown";
            }
        }
    }

    modules[moduleName] = version_;

    auto f = File(PROJECT_LOCK, "w");
    f.writeln("# pun.lock");
    f.writeln();

    import std.algorithm;

    foreach (mod; modules.keys.sort())
    {
        f.writeln(mod, "==", modules[mod]);
    }
    f.close();

    writeln("Updated ", PROJECT_LOCK);
}

void runScript(string[] args)
{
    string scriptFile = args[0];

    if (!exists(scriptFile))
    {
        writeln("Error: File not found: ", scriptFile);
        return;
    }

    string perlBin = "perl";
    string localLib = "lib";

    if (exists(PROJECT_CONFIG))
    {
        string perlVersion = null;
        string perlPath = null;

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

        if (perlPath && exists(perlPath))
        {
            perlBin = buildPath(perlPath, "bin", "perl");
        }
        else if (perlVersion)
        {
            string managedPath = getPerlPath(perlVersion);
            if (exists(managedPath))
            {
                perlBin = buildPath(managedPath, "bin", "perl");
            }
        }
    }

    string[string] env = environment.toAA();
    if (exists(localLib))
    {
        string absLibPath = absolutePath(localLib);
        string currentPerl5Lib = environment.get("PERL5LIB", "");
        env["PERL5LIB"] = currentPerl5Lib.length > 0 ? absLibPath ~ ":" ~ currentPerl5Lib
            : absLibPath;
    }

    auto result = spawnProcess([perlBin] ~ args, env);
    wait(result);
}
