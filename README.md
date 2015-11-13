# Using the Vivado-Git Scripts

In order to use this package to manage your Vivado projects in git, you first
need to set it up.  In order to continue to be able to get future updates, to
centralize development, and to avoid trouble with divergent codepaths as various
things fall out of date, or branch by coincidence, it is *strongly recommended*
that you use this project as a git submodule, rather than copying the scripts
into your repository directly.  Instructions on this method are below.

## Daily Usage & Repo Structure

This section explains the daily usage of the vivado-git support scripts.

Your repository will require some initial configuration on first use of the
vivado-git scripts, as well as on first checkout or updates involving
vivado-git, as explained in later sections.

### Repository Structure

A vivado-git managed repository has a specific structure.

* `vivado-git/`:  The vivado-git scripts are normally installed as symlinks into
  the `vivado-git/` submodule folder.
* `workspace/`:  Your checked out Vivado projects are stored in
  `workspace/MyProject/MyProject.xpr`.  This is where all of your project work
  using the Vivado GUI and tools will be done.  It is important that the
  subfolder name matches the project name exactly.  You may have as many Vivado
  projects as desired in a given workspace.
* `workspace.bak/`:  Checkout operations create a fresh workspace.  A backup of
  the previous workspace is created before each checkout in case of issues.
  *WARNING*: The previous backup is destroyed by this operation.
* `sources/`:  The tcl, vhdl, veralog, and other files related to your project
  are cannonically stored within the sources directory.  They will be copied
  here and managed automatically by the checkin script, and the checkout script
  will create Vivado projects that reference these files directly.

### Checkin & Checkout

When cloning, pulling, merging, or performing any other git-related operation,
it is necessary to operate on a checked-in version of your project.  You should
always checkin before any git operation, and checkout after any git operation.

To check your code in to the repository, make sure your Vivado environment files
have been sourced run `./checkin.pl`.  Then run `git status`, `git add`, and
`git commit` as necessary.  Note that after running checkin, your workspace
projects are no longer valid, and you must run checkout again.


**Always ensure no errors were emitted before committing!**

To check your code out from the repository, make sure your Vivado environment
files have been sourced, perform any relevant git pull or checkout operations,
and run `./checkout.pl`.  

## Existing-Repository Checkout

### Cloning your Vivado Project Repository Fresh

When cloning your Vivado project repository, it is possible to clone the
repository and checkout the vivado-git submodule all in one step, using:

```sh
git clone --recursive
```

### Pulling from or Updating your Vivado Project Repository

In order to update and initialize this submodule of your Vivado project
repository, after running `git pull` or `git clone`, you must run the following
commands:

The first time, if the submodule has never been used in your checkout before:

```sh
git submodule init
git submodule update
```

If you have already run this, but need to receive an update that has been
committed to your Vivado project repository (see the [Updates](#updates)
section below), you need only run the following command (however it will not hurt to
run both).

```sh
git submodule update
```

## New-Repository Setup

### Installation

In order to add this package as a git submodule, you need to change into your
existing git repository, first move any existing design files into the
appropriate project locations (see "Repository Structure" above), and execute
the following commands:

```sh
git submodule add https://github.com/uwcms/vivado-git.git
ln -s vivado-git/*pl ./
```

This will add the git submodule to your project.

Now you will need to ensure that your existing project or design files are
located in `workspace/` as explained in the "Repository Structure" section, and
run the checkin scripts for the initial import.  It is recommended that for the
initial import, you run checkin, checkout, and checkin again, before committing.
Note that after running checkin, your workspace project is no longer valid, and
you must run checkout again.

You will need to run `git commit` when you are finished, in order to make these
changes a part of your repository.  Do not forget to `git add` any relevant
files.

You may also be interested in using the example gitignore file provided in this
repository.  You *MUST* configure your gitignore to ignore the `workspace/` and
`workspace.bak/` directories!

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

### Updates

This project will continue to be updated and maintained.  These updates will NOT
automatically be applied to your project repositories!  This is a product of the
use of the git submodules system, and prevents possible upgrades from breaking
your projects without warning.  The version of this submodule that your project
is using, is automatically included by git-submodule as a part of your project
repository, and will always remain both consistent, and version-controlled.  As
such, updates are a manual procedure.

As this project will continue to advance and be maintained as new Vivado
versions are released or issues are found, you may occasionally wish to update
the version in use by your repositories, using the command below.  You will need
to use `git add` and `git commit` in your project repository to commit this
update, as shown.

```sh
git submodule update --remote vivado-git
git add vivado-git
git commit -m 'Updated vivado-git submodule version' vivado-git
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
