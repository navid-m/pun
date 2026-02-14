import std.stdio;
import std.getopt;
import std.file;
import std.path;
import std.process;
import std.string;
import std.algorithm;
import std.array;
import std.conv;

immutable string PUN_HOME = ".pun";
immutable string PERLS_DIR = "perls";
immutable string PROJECT_CONFIG = ".punrc";
immutable string PROJECT_LOCK = "pun.lock";

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
			initProject(args.length >= 3 ? args[2] : null);
			break;

		case "env":
			showEnv();
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
	writeln("pun - A perl version and package manager");
	writeln();
	writeln("Usage:");
	writeln("  pun install <version>  - Install a Perl version");
	writeln("  pun use <version>      - Switch to a Perl version");
	writeln("  pun list               - List installed Perl versions");
	writeln("  pun init [version]     - Initialize project with optional Perl version");
	writeln("  pun activate           - Activate project environment");
	writeln("  pun add <module>       - Add a CPAN module to project");
	writeln("  pun env                - Show environment setup commands");
}

string getPunHome()
{
	return buildPath(environment.get("HOME"), PUN_HOME);
}

string getPerlsDir()
{
	return buildPath(getPunHome(), PERLS_DIR);
}

string getPerlPath(string version_)
{
	return buildPath(getPerlsDir(), version_);
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

void initProject(string version_)
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

	writeln("Project initialized");
	if (version_)
	{
		writeln("  Perl version: ", version_);
	}
	writeln("  Local lib: lib/");
	writeln();
	writeln("Run: pun activate");
}

void activateProject()
{
	if (!exists(PROJECT_CONFIG))
	{
		writeln("No .punrc found. Run: pun init");
		return;
	}

	string perlVersion = null;
	string localLib = "lib";

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

	if (perlVersion)
	{
		string perlPath = getPerlPath(perlVersion);
		if (!exists(perlPath))
		{
			writeln("# Warning: Perl ", perlVersion, " not installed");
			writeln("# Run: pun install ", perlVersion);
		}
		else
		{
			string binPath = buildPath(perlPath, "bin");
			writeln("export PATH=\"", binPath, ":$PATH\"");
		}
	}

	string absLibPath = absolutePath(localLib);
	writeln("export PERL5LIB=\"", absLibPath, ":$PERL5LIB\"");
	writeln();
	writeln("Or source this:");
	writeln("  eval \"$(pun env)\"");
}

void addModule(string moduleName)
{
	if (!exists(PROJECT_CONFIG))
	{
		writeln("No .punrc found. Run: pun init");
		return;
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
	string localLib = "lib";

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

	if (perlVersion)
	{
		string perlPath = getPerlPath(perlVersion);
		if (exists(perlPath))
		{
			string binPath = buildPath(perlPath, "bin");
			writeln("export PATH=\"", binPath, ":$PATH\";");
		}
	}

	string absLibPath = absolutePath(localLib);
	writeln("export PERL5LIB=\"", absLibPath, ":$PERL5LIB\";");
}
