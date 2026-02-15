module pun.os.environment;

import std.string;
import std.stdio;
import std.path;
import std.file;
import std.algorithm;
import std.process;

import pun.local.globs;
import pun.local.projects;

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
    activateProject();
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
