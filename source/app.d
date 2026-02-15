import std.stdio;
import std.getopt;
import std.file;
import std.path;
import std.process;
import std.string;
import std.algorithm;
import std.array;
import std.conv;

import pun.environment;
import pun.globs;
import pun.projects;

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

        case "restore":
            restoreModules();
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

        case "run":
            if (args.length < 3)
            {
                writeln("Usage: pun run <file.pl>");
                return;
            }
            runScript(args[2 .. $]);
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
    writeln("  restore                 Restore modules from pun.lock");
    writeln("  run <file>              Run a Perl script with project environment");
    writeln("  env                     Show environment setup commands");
    writeln("  version                 Show pun version and exit");
}
