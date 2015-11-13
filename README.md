# Using the Vivado-Git Scripts

In order to use this package to manage your Vivado projects in git, you first
need to set it up.  In order to continue to be able to get future updates, to
centralize development, and to avoid trouble with divergent codepaths as various
things fall out of date, or branch by coincidence, it is *strongly recommended*
that you use this project as a git submodule, rather than copying the scripts
into your repository directly.  Instructions on this method are below.

## New-Repository Setup

### Installation

In order to add this package as a git submodule, you need to change into your
existing git repository, and execute the following commands:

```sh
git submodule add https://github.com/uwcms/vivado-git.git
ln -s vivado-git/*pl ./
```

This will add the git submodule to your project.  You will need to run `git
commit` when you are finished, in order to make these changes a part of your
repository.  Do not forget to `git add` the symlinks you created.

You may also be interested in using the example gitignore file provided in this
repository.

### Configuration

In order to properly handle Vivado projects, it is important to maintain a
synchronized environment between developers.  All developers should use the same
Vivado version.  In order to prevent time consuming accidents, the checkin and
checkout scripts verify that the current vivado version is the one that has been
configured for the repository.

In order to configure this, you will need to create a file `RepoVivadoVersion`
like so, which should be committed to your repository:

```sh
echo '2014.4' > RepoVivadoVersion
```

### Optional Advanced Configuration for Contributors [Expert]

In order to make your project usable by people who check it out without the
direct use of a Github account, it is necessary to use the https transport for
the submodule declaration.  This *should not* be changed.  If you wish to
contribute to @uwcms/vivado-git using an SSH url instead of the default HTTPS,
you should follow the instructions below.  If you do not intend to contribute to
the @uwcms/vivado-git repository specifically (*not your Vivado project's
repository*), you may skip this section.

In order to reconfigure your local copy only to use the ssh github url, you
should run the following command:

```sh
git config submodule.vivado-git.url git@github.com:uwcms/vivado-git.git
```

You should also edit the file `.git/modules/vivado-git/config` if it exists, and
replace the url in the `remote` section, shown below:
```ini
[remote "origin"]
	url = https://github.com/uwcms/vivado-git.git
	fetch = +refs/heads/*:refs/remotes/origin/*
```

These changes will not be stored in or affect your repository, and will not be
visible to or interfere with other contributors.  You will need to perform these
operations in any clone where you wish to contribute to @uwcms/vivado-git.
