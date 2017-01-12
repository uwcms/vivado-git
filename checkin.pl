#!/usr/bin/perl
use warnings;
use strict;
use Cwd qw(getcwd abs_path);
use File::Spec;
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

our $DEBUG = 0;
our $SAVE_RAW_TCL = 0;

my %MESSAGES;
my %PROJECT_REPO_DEPS;

for my $ProjectPath (glob("workspace/*/*.xpr")) {
	next unless $ProjectPath =~ m!^workspace/([^/]+)/([^/]+)\.xpr$!;
	my $ProjectFilename = $2;
	my $ProjectCanonicalName = $1;
	my $SourcesBdDir = sprintf("sources/%s.bd", $ProjectCanonicalName);
	my $ProjectDir = sprintf("%s/workspace/%s", getcwd(), $ProjectCanonicalName);
	$MESSAGES{$ProjectCanonicalName} = [];

	mkdir('sources');
	mkdir(sprintf("sources/%s", $ProjectCanonicalName));
	mkdir($SourcesBdDir);
	unlink(glob("$SourcesBdDir/*"));

	printf "~"x80 ."\n";
	printf "~~~ Processing Project: %s\n", $ProjectCanonicalName;
	printf "~~~\n";
	printf "~~~ Exporting Project TCL from Vivado\n";
	open(VIVADO, '|-', 'vivado', '-nojournal', '-nolog', '-mode', 'tcl', $ProjectPath);
	printf VIVADO "write_project_tcl -force \".exported.tcl\"\n";

	printf VIVADO "foreach {bd_file} [get_files -filter {FILE_TYPE == \"Block Designs\"}] {\n";
	printf VIVADO "	open_bd_design \$bd_file\n";
	printf VIVADO "	write_bd_tcl \"%s/[file rootname [file tail \$bd_file]].tcl\"\n", $SourcesBdDir;
	printf VIVADO "	close_bd_design [file rootname [file tail \$bd_file]]\n";
	printf VIVADO "}\n";
	close(VIVADO);

	if (WEXITSTATUS($?)) {
		push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'CRITICAL ERROR', Message => sprintf("Vivado exited with an unexpected status code after project export: %s.  Aborting.  The project has NOT been exported or updated!", WEXITSTATUS($?)) };
		unlink('.exported.tcl');
		next;
	}
	printf "\n";
	printf "~~~ Analyzing & Rewriting Project TCL and Copying source files\n";
	process_tcl('.exported.tcl', '.processed.tcl', $ProjectCanonicalName, $ProjectDir);
	rename('.processed.tcl', sprintf("sources/%s.tcl", $ProjectCanonicalName));
	rename('.exported.tcl', sprintf("sources/%s.tcl.raw", $ProjectCanonicalName)) if ($DEBUG || $SAVE_RAW_TCL);
	unlink('.processed.tcl');
	unlink('.exported.tcl');

	printf "\n";
	printf "~~~\n";
	printf "~~~ Finished processing project %s\n", $ProjectCanonicalName;
	printf "~"x80 ."\n";

	if (@{$MESSAGES{$ProjectCanonicalName}}) {
		printf "~~~ MESSAGES FOR PROJECT %s\n", $ProjectCanonicalName;
		printf "~~~\n";
		for my $Message (@{$MESSAGES{$ProjectCanonicalName}}) {
			if ($DEBUG) {
				printf "~~~ [%4d] %s: %s\n", $Message->{Line}, $Message->{Severity}, $Message->{Message};
			} else {
				printf "~~~ %s: %s\n", $Message->{Severity}, $Message->{Message};
			}
		}
		printf "~~~\n";
	}
	printf "\n";
}

if (-e 'workspace/ip_repo') {
	printf "\n";
	printf "~"x80 ."\n";
	printf "~~~ COPYING IP_REPO\n";
	printf "~~~\n";
	system('rsync',
		'-rhtci', '--del',
		'workspace/ip_repo/',
		'ip_repo_sources/',
		'--filter', 'S /*/bd',
		'--filter', 'S /*/component.xml',
		'--filter', 'S /*/hdl',
		'--filter', 'S /*/xgui',
		'--filter', 'S /*/drivers',
		'--filter', 'H /*/*');
	printf "~~~\n";
	printf "\n";
}

open(DEPORDER, '>', 'projects.list');
printf DEPORDER "%s\n", join "\n", process_deps(%PROJECT_REPO_DEPS);
close(DEPORDER);

my $Worry = 0;
my %MessageTotals;
for my $ProjectCanonicalName (keys %MESSAGES) {
	if (@{$MESSAGES{$ProjectCanonicalName}}) {
		printf "\n\n" unless (%MessageTotals);
		printf "~"x80 ."\n";
		printf "~~~ MESSAGES FOR PROJECT %s\n", $ProjectCanonicalName;
		printf "~~~\n";
		for my $Message (@{$MESSAGES{$ProjectCanonicalName}}) {
			if ($DEBUG) {
				printf "~~~ [%4d] %s: %s\n", $Message->{Line}, $Message->{Severity}, $Message->{Message};
			} else {
				printf "~~~ %s: %s\n", $Message->{Severity}, $Message->{Message};
			}
			$MessageTotals{$Message->{Severity}} = 0 unless exists($MessageTotals{$Message->{Severity}});
			$MessageTotals{$Message->{Severity}}++;
			$Worry++ if ($Message->{Hazard});
		}
		printf "~~~\n";
	}
}
if (grep { $_ } values %MessageTotals) {
	printf "~"x80 ."\n";
	printf "\n";
	system("git", "status");
	printf "\n";
	for my $MessageType (sort keys %MessageTotals) {
		printf "~~~ %u %s messages\n", $MessageTotals{$MessageType}, $MessageType;
	}
	printf "\n";
	printf "~~~ Please review them carefully and make sure none are dangerous before committing.\n";
	printf "~~~ Always review 'git status' before committing!.\n";
	exit(2);
}
else {
	printf "~~~ No issues encountered.  Projects exported and ready to add to git.\n";
	printf "~~~ Always review 'git status' before committing!.\n";
	printf "\n";
	system("git", "status");
	exit(0);
}

sub process_tcl {
	my $TclInFile = shift;
	my $TclOutFile = shift;
	my $ProjectCanonicalName = shift;
	my $ProjectDir = shift;

	$PROJECT_REPO_DEPS{$ProjectCanonicalName} = [];

	if (!open(TCLOUT, '>', $TclOutFile)) {
		push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'CRITICAL ERROR', Message => sprintf("Unable to open intermediate file \"%s\".  Aborting.  The project has NOT been exported or updated!", $TclOutFile) };
		unlink($TclOutFile);
		return;
	}
	if (!open(TCLIN, '<', $TclInFile)) {
		push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'CRITICAL ERROR', Message => sprintf("Unable to open intermediate file \"%s\".  Aborting.  The project has NOT been exported or updated!", $TclInFile) };
		close(TCLOUT);
		unlink($TclOutFile);
		return;
	}

	my %SourcesIndex;
	my %TargetsIndex;

	my $FileListing = 0;
	my $InitialComments = 1;
	my $LastComment = "";
	my $BD_Inject_State = 0;
	my @Discarded_BD_Wrappers;
	my $FileList_State = 0;
	my $FileProperty_Disarm = 0;
	my $Current_SetFile = undef;
	while (my $Line = <TCLIN>) {
		my $KeepLine = 1;
		my $PathSubstitute = 1;
		chomp $Line;

		if ($InitialComments...($Line =~ /^(?!#)/)) {
			# Remove inital comments for git consistency.
			$InitialComments = 0;
			$KeepLine = 0 unless ($DEBUG);
		}

		if ($Line =~ /^#\s+(.*)$/) {
			$LastComment = $1;
		}

		if ($Line =~ /^set orig_proj_dir /) {
			$Line = sprintf('set orig_proj_dir "[file normalize "sources/%s"]"', $ProjectCanonicalName);
		}

		if ($Line =~ /^create_project /) {
			$Line = sprintf('create_project %s workspace/%s', $ProjectCanonicalName, $ProjectCanonicalName);
		}
		
		if ($Line =~ /^set obj \[get_projects \S+\]/) {
			$Line = sprintf('set obj [get_projects %s]', $ProjectCanonicalName);
		}

		if (($FileListing == 0 && $Line =~ /^# 2\. The following source\(s\) files that were local or imported into the original project/)...($Line =~ /^\s*$/)) {
			$FileListing = 1;

			if ($Line =~ /^#\s+"(.*)"$/) {
				my $RawFile = $1;
				my $File = get_path($RawFile, 1, $ProjectCanonicalName, 0, undef);

				if ($File =~ m!\.srcs/[^ /]+/bd/([^ /]+)/\1.bd$!) {
					push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 0, Severity => 'INFO', Message => sprintf("Discarding source file (Block Designs exported separately): %s", $File) };
				}
				elsif ($File =~ m!\.srcs/[^ /]+/bd/([^ /]+)/hdl/\1_wrapper\.v(?:hd)?$!) {
					push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 0, Severity => 'INFO', Message => sprintf("Discarding source file (Block Design auto-wrapper will be regenerated): %s", $File) };
					push @Discarded_BD_Wrappers, $1;
					$SourcesIndex{abs_path($File)} = undef;
				}
				else {
					my $Target = get_path($RawFile, 1, $ProjectCanonicalName, 1, undef);
					if (!-e $File) {
						push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'WARNING', Message => sprintf("Unable to locate/copy specified source file: %s", $1) };
					}
					else {
						if ($File ne $Target) {
							if (exists($TargetsIndex{abs_path($Target)}) && $TargetsIndex{abs_path($Target)} != abs_path($File)) {
								$Target = get_new_file_target($Target);
								push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'CRITICAL WARNING', Message => sprintf("DUPLICATE TARGET FILE in repository sources: \"%s\" is being remapped to \"%s\" in violation of the pattern.  The scripts MAY not perfectly handle this case through future iterations of checkin.  Be attentive!", $File, $Target) };
							}

							my $TargetDir = $Target;
							$TargetDir =~ s#/[^/]+$##;
							system('mkdir', '-p', '--', $TargetDir);
							system('cp', '-a', '--', $File, $Target);
							push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 0, Severity => 'INFO', Message => sprintf("Relocating file to repository sources: %s", $File) };
						}

						push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 0, Severity => 'DEBUG INFO', Message => sprintf("Registering Target: %s", $Target) } if ($DEBUG);
						$SourcesIndex{abs_path($File)} = abs_path($Target);
						$TargetsIndex{abs_path($Target)} = abs_path($File);
					}
				}
			}
		}

		if ($Line =~ /^set files \[list \\$/) {
			$FileList_State = 1; # In list.
		}
		if ($FileList_State) {
			if ($Line =~ /^\s*$/) {
				$FileList_State = 0; # Reset state, we are finished.
			}
			elsif ($Line =~ m![^ /]+\.srcs/[^ /]+/bd/([^ /]+)/\1.bd"! ||
				$Line =~ m![^ /]+\.srcs/[^ /]+/bd/([^ /]+)/hdl/\1_wrapper\.v(?:hd)?"!) {
				$KeepLine = 0;
			}
			elsif ($Line =~ /^\s+"\[file normalize "(.*)"\]"\\$/) {
				my $File = get_path($1, 1, $ProjectCanonicalName, 1, \%SourcesIndex);

				if (-e $File) {
					$FileList_State = 2; # Found a valid file to keep.
				}
				else {
					$KeepLine = 0;
					push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'CRITICAL WARNING', Message => sprintf("Unable to locate/register specified source file \"%s\".  File excluded.", $File) };
				}
			}
			elsif ($Line =~ /^add_files /) {
				if ($FileList_State == 1) {
					# We didnt have any actual files in this list, that we kept.
					# Disable the add_files, as it will error.
					$Line = "# $Line";
				}
				$FileList_State = 0; # And finish.
			}
			elsif ($Line =~ /^set imported_files /) {
				if ($FileList_State == 1) {
					# We didnt have any actual files in this list, that we kept.
					# Disable the import_files, as it will error.
					$Line = "# $Line";
				}
				else {
					if ($Line =~ /set imported_files \[import_files -fileset (\S+) /) {
						$Line = sprintf("add_files -norecurse -fileset [get_filesets %s] \$files", $1);
					}
					else {
						push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'WARNING', Message => sprintf("Unable to parse import_files fileset parameter in \"%s\".  Files will be imported, not added.  Report the bug.", $Line) };
					}
				}
				$FileList_State = 0; # And finish.
			}
		}

		if ($Line =~ m!^set file "(.*)"$!) {
			$Current_SetFile = $1;
			if ($Current_SetFile =~ /^\[file normalize "(.*)"\]$/) {
				$Current_SetFile = $1;
			}
			$FileProperty_Disarm = 2 unless (-e get_path($1, 1, $ProjectCanonicalName, 0, \%SourcesIndex));
		}
		elsif ($Line =~ /^\s*$/) {
			$Current_SetFile = undef;
		}

		if ($Line =~ m!^set file ".*\.srcs/[^ /]+/bd/([^ /]+)/hdl/\1_wrapper\.v(?:hd)?"$!) {
			$FileProperty_Disarm = 1; # Property block is to be discarded.
		}
		if ($Line =~ m!^set file ".*\.srcs/[^ /]+/bd/([^ /]+)/\1\.bd"$!) {
			$FileProperty_Disarm = 1; # Property block is to be discarded.
		}
		if ($FileProperty_Disarm) {
			if ($Line =~ /^\s*$/) {
				$FileProperty_Disarm = 0; # Reset state, we are finished.
			}
			elsif ($FileProperty_Disarm == 1) {
				$KeepLine = 0;
			}
			elsif ($FileProperty_Disarm == 2) {
				$Line = "# $Line";
				$PathSubstitute = 0;
			}
		}
		elsif ($Line =~ /^set file_imported \[import_files -fileset (\S+) \$file\]$/) {
			$Line = sprintf("add_files -norecurse -fileset [get_filesets %s] \$file", $1);
		}

		# Vivado 2014.4 searches the entire directory recursively for IP-XACT files, this symlink is no longer required.  (Was it before..?)
		#
		# if ($Line =~ /^set_property "file_type" "IP-XACT" \$file_obj$/ && $Current_SetFile =~ m!workspace\/\Q$ProjectCanonicalName\E/component\.xml$!) {
		# 	#$origin_dir/workspace/v7_loader/v7_loader.srcs/sources_1/imports/imports/component.xml
		# 	printf TCLOUT "file link -symbolic workspace/%s/component.xml ../../sources/%s/component.xml\n", $ProjectCanonicalName, $ProjectCanonicalName;
		# }

		if ($Line =~ /^set_property "file_type" "Unknown" \$file_obj$/) {
			$Line = "#$Line";
		}

		if ($BD_Inject_State == 0 && $Line =~ /^# Set \S+ fileset object$/) {
			$BD_Inject_State = 1;
			if (glob(sprintf("sources/%s.bd/*.tcl", $ProjectCanonicalName))) {
				printf TCLOUT "puts \"*** BEGINNING TO RECONSTRUCT BLOCK DESIGNS\"\n";
				printf TCLOUT "foreach {bd_file} [glob sources/%s.bd/*] {\n", $ProjectCanonicalName;
				printf TCLOUT "	source \$bd_file\n";
				printf TCLOUT "}\n";
				foreach my $BD_Wrapper (@Discarded_BD_Wrappers) {
					printf TCLOUT "add_files -norecurse -force [make_wrapper -files [get_files %s.bd] -top]\n", $BD_Wrapper;
				}
				if (@Discarded_BD_Wrappers) {
					printf TCLOUT "foreach {fileset} [get_filesets -filter {FILESET_TYPE =~ {*Srcs}}] {\n";
					printf TCLOUT " update_compile_order -fileset \$fileset\n";
					printf TCLOUT "}\n";
				}
				printf TCLOUT "puts \"*** FINISHED RECONSTRUCTING BLOCK DESIGNS\"\n";
				printf TCLOUT "\n";
			}
		}

		if ($Line =~ /^set_property "ip_repo_paths" "(.*)" \$obj$/) {
			printf TCLOUT "# $Line\n";
			# set_property "ip_repo_paths" "[file normalize "$origin_dir/../workspace/mmcspi"] [file normalize "$origin_dir/../workspace/v7_loader"]" $obj
			# set_property "ip_repo_paths" "[file normalize "$origin_dir/workspace/startup_override/startup_override.srcs/sources_1/new"]" $obj

			my $RepoPaths = $1;
			$PathSubstitute = 0;

			my @RepoPaths = split /(?<=\]) (?=\[)/, $RepoPaths;
			my @NewRepoPaths;
			foreach my $RepoPath (@RepoPaths) {
				unless ($RepoPath =~ /^\[file normalize "([^"]+)"\]$/) {
					push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'WARNING', Message => sprintf("Ignoring unparsable ip_repo_path: %s", $RepoPath) };
					next;
				}
				$RepoPath = get_path($1,1,$ProjectCanonicalName,0,undef);
				next unless ($RepoPath);
				if ($RepoPath !~ m!^workspace/ip_repo!) {
					$RepoPath =~ s/^workspace\//sources\//;
				}

				if (!($RepoPath =~ m!^sources/([^/]+)(?:/.*)?$!)) {
					push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'WARNING', Message => sprintf("External ip_repo_path \"%s\" will NOT be processed! Strongly consider relocating it to workspace/ip_project", $RepoPath) };
				}
				elsif ($1 ne $ProjectCanonicalName) {
					#push @{$PROJECT_REPO_DEPS{$ProjectCanonicalName}}, $1;
				}
				push @NewRepoPaths, sprintf('[file normalize "%s"]', $RepoPath);
			}
			$Line = sprintf('set_property "ip_repo_paths" "%s" $obj', join(" ", @NewRepoPaths));
		}

		if ($PathSubstitute) {
			# It appears to outright lie, saying that the file is relative to $origin_dir when it is actually relative to sources/$ProjectCannonicalName
			# set_property "steps.write_bitstream.tcl.pre" "[file normalize "$origin_dir/CTP7.srcs/sources_1/imports/CTP7/ignore_LUTLP1.tcl"]" $obj
			if ($Line =~ /^set_property "steps\.([^"]+)\.tcl\.(pre|post)" "\[file normalize "\$origin_dir\/([^[\/\$].*)"]" \$obj$/) {
				if (-e "sources/$ProjectCanonicalName/$3") {
					$Line = sprintf('set_property "steps.%s.tcl.%s" "[file normalize "sources/%s/%s"]" $obj', $1, $2, $ProjectCanonicalName, $3);
				}
			}

			$Line =~ s/"(\$(?:origin_dir|proj_dir)\/[^"]*)"/sprintf('"%s"', get_path($1,1,$ProjectCanonicalName,1,\%SourcesIndex))/eg;

			if ($Line =~ /^set_property "steps\.([^"]+)\.tcl\.(pre|post)" "([^[\/\$].*)" \$obj$/) {
				$Line =~ s/" "/" "[pwd]\//;
			}
		}

		printf TCLOUT "%s\n", $Line if $KeepLine;
	}

	printf "\n";
	printf "~~~ Updating any component.xml files\n";

	open(FINDXML, '-|', 'find', sprintf('sources/%s', $ProjectCanonicalName), '-type', 'f', '-name', 'component.xml');
	while (my $ComponentXML = <FINDXML>) {
		chomp $ComponentXML;
		my $ComponentPath = $ComponentXML;
		$ComponentPath =~ s#/component\.xml$##;

		printf "~~~ Processing %s\n", $ComponentXML;

		my $WSPath = $ComponentPath;
		$WSPath =~ s/^sources/workspace/;
		if ($WSPath ne $ComponentPath && -d sprintf("%s/xgui/", $WSPath)) {
			system('rsync', '-ahv', '--del', sprintf("%s/xgui/", $WSPath), sprintf("%s/xgui/", $ComponentPath));
			push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 0, Severity => 'INFO', Message => sprintf("Relocating directory to repository sources: workspace/%s/xgui", $ProjectCanonicalName) };
		}

		process_componentxml($ComponentXML, '.component.xml', $ProjectCanonicalName, $ComponentPath, \%TargetsIndex);
		rename('.component.xml', $ComponentXML);
		unlink('.component.xml');
	}
	close(FINDXML);

	printf "\n";
	printf "~~~ Purging unused sources\n";

	open(FIND, '-|', 'find', sprintf('sources/%s', $ProjectCanonicalName), '-type', 'f');
	while (my $File = <FIND>) {
		chomp $File;
		$File = abs_path($File);
		unlink($File) unless (exists($TargetsIndex{$File}));
		push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 0, Severity => 'DEBUG WARNING', Message => sprintf("Unlinked \"%s\".", $File) } if ($DEBUG && !exists($TargetsIndex{$File}));
	}
	close(FIND);
	system('find', sprintf('sources/%s', $ProjectCanonicalName), '-depth', '-type', 'd', '-exec', 'rmdir', '--ignore-fail-on-non-empty', '{}', ';');
}
sub process_componentxml {
	my $XML_In = shift;
	my $XML_Out = shift;
	my $ProjectCanonicalName = shift;
	my $ComponentPath = shift;
	my $TargetsIndex = shift;

	if (!open(XMLOUT, '>', $XML_Out)) {
		push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'CRITICAL ERROR', Message => sprintf("Unable to open intermediate file \"%s\".  Aborting.  This project's IP package may be unusuable!", $XML_Out) };
		unlink($XML_Out);
		return;
	}
	if (!open(XMLIN, '<', $XML_In)) {
		push @{$MESSAGES{$ProjectCanonicalName}}, { Line => __LINE__, Hazard => 1, Severity => 'CRITICAL ERROR', Message => sprintf("Unable to open intermediate file \"%s\".  Aborting.  This project's IP package may be unusable!", $XML_In) };
		close(TCLOUT);
		unlink($XML_Out);
		return;
	}

	while (my $Line = <XMLIN>) {
		chomp $Line;

		if (($Line =~ /^\s*<spirit:file>$/)...($Line =~ /^\s*<\/spirit:file>$/)) {
			if ($Line =~ /^(\s*)<spirit:name>(.*)<\/spirit:name>$/) {
				my $Indent = $1;
				my $File = abs_path(File::Spec->rel2abs($2, $ComponentPath));
				if ($File) {
					$Line = sprintf("%s<spirit:name>%s</spirit:name>", $Indent, File::Spec->abs2rel($File, $ComponentPath));
					$TargetsIndex->{$File} = $File;
				}
			}
		}

		printf XMLOUT "%s\n", $Line;
	}
}

sub _get_path_update_for_xcix {
	# Vivado 2016.1 will report files as /ip/module/module.xci when they are actually packaged as /ip/module.xcix
	my $Path = shift;
	return $Path unless $Path =~ /\.xci$/;
	return $Path if -e $Path;
	my $AltPath = $Path;
	$AltPath =~ s!/ip/([^/]+)/\g1\.xci!/ip/$1.xcix!;
	return $AltPath if -e ($AltPath);
	my $SourcePath = $AltPath;
	$SourcePath =~ s!(^|/)workspace/!$1sources/!;
	return $AltPath if -e ($SourcePath);
	return $Path;
}

sub get_path {
	my $Path = shift;
	my $Relative = shift;
	my $Project = shift;
	my $TargetSources = shift;
	my $SourcesIndex = shift;

	$Path =~ s/\$origin_dir\//.\//;
	$Path =~ s/\$proj_dir\//workspace\/$Project\//;

	my $OrigPath = $Path;
	$Path = _get_path_update_for_xcix($Path) if defined($Path);
	$Path = abs_path($Path);
	if (!defined($Path) || ! -e($Path)) {
		if (defined $SourcesIndex) {
			foreach my $SourcePath (keys %$SourcesIndex) {
				if ($SourcePath =~ /(^|\/|(?=\/))\Q$OrigPath\E$/) {
					$SourcePath = _get_path_update_for_xcix($SourcePath) if defined($SourcePath);
					$SourcePath = abs_path($SourcePath);
					if (!defined($SourcePath) || ! -e($SourcePath)) {
						next;
					}
					else {
						$Path = $SourcePath;
						last;
					}
				}
			}
		}
		if (!defined($Path) || ! -e($Path)) {
			push @{$MESSAGES{$Project}}, { Line => __LINE__, Hazard => 1, Severity => 'WARNING', Message => sprintf("Missing path: %s", $OrigPath) };
			return '';
		}
	}

	my $pwd = abs_path(getcwd());
	if (defined($Project) && $TargetSources) {
		if ($Path =~ m!^\Q$pwd\E/(?:workspace|sources)/([^/]+)/(.*)!) {
			$Path = sprintf("%s/sources/%s/%s", $pwd, $1, $2);
		}
		else {
			$Path = sprintf("%s/sources/%s/%s", $pwd, $Project, $Path);
		}
	}
	if ($Relative) {
		$Path =  File::Spec->abs2rel($Path, '.');
	}
	return $Path;
}

sub get_new_file_target {
	my $Target = shift;
	my $Int = 0;
	my $Ext = '';
	if ($Target =~ /^(.+)(\.[^\/.]+)$/) {
		$Target = $1;
		$Ext = $2;
	}
	if ($Ext =~ /^\.[0-9]+$/) {
		$Target = $Target . $Ext;
		$Ext = '';
	}
	if ($Target =~ /^(.+)\.([0-9]+)$/) {
		$Target = $1;
		$Int = int($2);
	}
	while ($Int < 500) {
		my $Candidate = sprintf("%s.%u%s", $Target, $Int, $Ext);
		return $Candidate unless (-e $Candidate);
		$Int++;
	}
	die(sprintf("Unable to produce suitable alternate target file candidate! Target: \"%s\", Ext: \"%s\"", $Target, $Ext));
}

sub process_deps {
	my %Deps = @_;

	my %Seen = map { ($_,0) } keys %Deps;
	my @Order;
	my $Fail = 0;

	sub do_procdep {
		my $Token = shift;
		my $Deps = shift;
		my $Seen = shift;
		my $Order = shift;
		my $Fail = shift;

		return if ($Seen->{$Token} == 2);
		if ($Seen->{$Token} == 1) {
			$$Fail = 1;
			return;
		}
		$Seen->{$Token} = 1;

		if (exists($Deps->{$Token})) {
			foreach my $Dep (sort @{$Deps->{$Token}}) {
				do_procdep($Dep, $Deps, $Seen, $Order, $Fail);
				return if $$Fail;
			}
		}
		push @$Order, $Token;
		$Seen->{$Token} = 2;
	}

	for my $Dep (sort keys %Deps) {
		do_procdep($Dep, \%Deps, \%Seen, \@Order, \$Fail);
	}
	return () if ($Fail);
	return @Order;
}
