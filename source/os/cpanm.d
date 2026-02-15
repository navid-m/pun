module pun.os.cpanm;

import std.stdio;
import std.process;

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
