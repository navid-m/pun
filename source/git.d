module pun.git;

import std.stdio;

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
