#!/usr/bin/perl
use warnings;
use strict;
use Cwd qw(getcwd);
use POSIX qw(WEXITSTATUS);

open(RVV, '<', 'RepoVivadoVersion');
my $VIVADO_VERSION = <RVV>; chomp $VIVADO_VERSION;
close(RVV);
unless ($VIVADO_VERSION) {
	printf "Unable to detect the Vivado version in use in this repository.\n";
	exit(1);
}
if ($ENV{PATH} !~ m!/Vivado/\Q$VIVADO_VERSION\E(/\.)?/bin!) {
	printf "You are not running Vivado $VIVADO_VERSION or have not sourced the environment initialization scripts.  Aborting.\n";
	exit(1);
}

my %MESSAGES;

printf "~~~ Destroying backup workspace! ~~~\n";
system('rm', '-rf', 'workspace.bak');
printf "\n";
printf "~~~ Backing up and replacing current workspace\n";
if (-e 'workspace' && !rename('workspace', 'workspace.bak')) {
	printf "~~~ Failed to rename workspace to workspace.bak.  Aborting.\n";
	exit(2);
}
if (!mkdir('workspace')) {
	printf "~~~ Failed to create workspace.  Aborting.\n";
	exit(2);
}

open(PROJECTLIST, '<', 'projects.list');
while (my $ProjectCanonicalName = <PROJECTLIST>) {
	chomp $ProjectCanonicalName;
	my $SourcesDir = sprintf("sources/%s", $ProjectCanonicalName);
	my $ProjectDir = sprintf("%s/workspace/%s", getcwd(), $ProjectCanonicalName);
	$MESSAGES{$ProjectCanonicalName} = [];

	printf "~"x80 ."\n";
	printf "~~~ Processing Project: %s\n", $ProjectCanonicalName;
	printf "~~~\n";
	printf "~~~ Sourcing Project TCL in Vivado\n";
	system('vivado', '-mode', 'batch', '-nojournal', '-nolog', '-source', sprintf("sources/%s.tcl", $ProjectCanonicalName));
	if (WEXITSTATUS($?)) {
		push @{$MESSAGES{$ProjectCanonicalName}}, { Severity => 'CRITICAL ERROR', Message => sprintf("Vivado exited with an unexpected status code after project regeneration: %s.  Aborting.  The project has NOT necessarily been safely or fully created!", WEXITSTATUS($?)) };
	}
	else {
		printf "~~~ Running any project-specific initialization scripts\n";
		my @InitScripts;
		push @InitScripts, sprintf("initscripts/%s.pl", $ProjectCanonicalName);
		push @InitScripts, sprintf("initscripts/%s.sh", $ProjectCanonicalName);
		push @InitScripts, sprintf("initscripts/%s.py", $ProjectCanonicalName);
		for my $InitScript (@InitScripts) {
			if (-x $InitScript) { 
				printf "~~~ Running %s\n", $InitScript;
				system($InitScript, sprintf("%s/%s.xpr", $ProjectDir, $ProjectCanonicalName));
				if (WEXITSTATUS($?)) {
					push @{$MESSAGES{$ProjectCanonicalName}}, { Severity => 'WARNING', Message => sprintf("Project initialization script %s exited with nonzero status: %s!", $InitScript, WEXITSTATUS($?)) };
				}
			}
		}
		my $InitScript = sprintf("initscripts/%s.tcl", $ProjectCanonicalName);
		if (-f $InitScript) { 
			printf "~~~ Running %s\n", $InitScript;
			system('vivado', '-mode', 'batch', '-nojournal', '-nolog', '-source', $InitScript, sprintf("%s/%s.xpr", $ProjectDir, $ProjectCanonicalName));
			if (WEXITSTATUS($?)) {
				push @{$MESSAGES{$ProjectCanonicalName}}, { Severity => 'WARNING', Message => sprintf("Project initialization script %s exited with nonzero status: %s!", $InitScript, WEXITSTATUS($?)) };
			}
		}
	}

	printf "~~~\n";
	printf "~~~ Finished processing project %s\n", $ProjectCanonicalName;

	printf "\n";
	printf "\n";
	if (@{$MESSAGES{$ProjectCanonicalName}}) {
		printf "~"x80 ."\n";
		printf "~~~ MESSAGES FOR PROJECT %s\n", $ProjectCanonicalName;
		printf "~~~\n";
		for my $Message (@{$MESSAGES{$ProjectCanonicalName}}) {
			printf "~~~ %s: %s\n", $Message->{Severity}, $Message->{Message};
		}
		printf "~~~\n";
	}
}
my %MessageTotals;
for my $ProjectCanonicalName (keys %MESSAGES) {
	if (@{$MESSAGES{$ProjectCanonicalName}}) {
		printf "\n\n\n" unless (%MessageTotals);
		printf "~"x80 ."\n";
		printf "~~~ MESSAGES FOR PROJECT %s\n", $ProjectCanonicalName;
		printf "~~~\n";
		for my $Message (@{$MESSAGES{$ProjectCanonicalName}}) {
			printf "~~~ %s: %s\n", $Message->{Severity}, $Message->{Message};
			$MessageTotals{$Message->{Severity}} = 0 unless exists($MessageTotals{$Message->{Severity}});
			$MessageTotals{$Message->{Severity}}++;
		}
		printf "~~~\n";
	}
}
if (grep { $_ } values %MessageTotals) {
	printf "~"x80 ."\n";
	for my $MessageType (sort keys %MessageTotals) {
		printf "~~~ %u %s messages\n", $MessageTotals{$MessageType}, $MessageType;
	}
	printf "~~~ Please review them carefully and make sure none are dangerous before proceeding.\n";
}
else {
	printf "~~~ No issues encountered.  Projects generated and ready to use.\n";
}
