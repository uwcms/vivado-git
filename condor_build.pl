#!/usr/bin/perl
use warnings;
use strict;
use Getopt::Long;

open(RVV, '<', 'RepoVivadoVersion');
my $VIVADO_VERSION = <RVV>; chomp $VIVADO_VERSION;
close(RVV);
unless ($VIVADO_VERSION) {
	printf "Unable to detect the Vivado version in use in this repository.\n";
	exit(1);
}

our $OPT_DO_RUN = undef;
our $OPT_PROJECT = undef;
our $OPT_RUN = undef;
our $OPT_STREAM_STDOUT = 0;
our $OPT_ENABLE_LOG = 1;
GetOptions(
	'do-run=s' => \$OPT_DO_RUN,
	'p|project=s' => \$OPT_PROJECT,
	'r|run=s' => \$OPT_RUN,
	's|stream-stdout!' => \$OPT_STREAM_STDOUT,
	'l|enable-log!' => \$OPT_ENABLE_LOG,
);
if (!defined($OPT_PROJECT) || !defined($OPT_RUN)) {
	printf "%s -sl -p ProjectName -r impl_1\n", $0;
	printf "\t-p|--project        The project to build\n";
	printf "\t-r|--run            The run to launch\n";
	printf "\t-s|--stream-stdout  Produce realtime stdout/stderr logs\n";
	printf "\t--no-enable-log     Do not generate the condor job log file\n";
	exit(0);
}

if (!defined $OPT_DO_RUN) {
	open(CONDOR, '|-', 'condor_submit') or die "Cannot run condor_submit: $!";
	printf CONDOR "executable = condor_build.pl\n";
	printf CONDOR "arguments = --do-run=\$(Cluster) --project=%s --run=%s %s\n", $OPT_PROJECT, $OPT_RUN, ($OPT_STREAM_STDOUT ? "--stream-stdout" : "");
	printf CONDOR "should_transfer_files = yes\n";
	printf CONDOR "when_to_transfer_output = on_exit\n";
	printf CONDOR "transfer_input_files = .\n";
	printf CONDOR "transfer_output_files = run-%s.%s.\$(Cluster)\n", $OPT_PROJECT, $OPT_RUN;
	printf CONDOR "output = run-%s.%s.\$(Cluster).stdout\n", $OPT_PROJECT, $OPT_RUN if ($OPT_STREAM_STDOUT);
	printf CONDOR "error = run-%s.%s.\$(Cluster).stderr\n", $OPT_PROJECT, $OPT_RUN if ($OPT_STREAM_STDOUT);
	printf CONDOR "log = run-%s.%s.\$(Cluster).condor_log\n", $OPT_PROJECT, $OPT_RUN if ($OPT_ENABLE_LOG);
	printf CONDOR "Requirements = HasAFS_OSG && regexp(\"^<?(144\\.92\\.18[0-4]\\.|128\\.104\\.2[89]\\.)\", MyAddress)\n";
	printf CONDOR "\n";
	printf CONDOR "stream_output = true\n" if ($OPT_STREAM_STDOUT);
	printf CONDOR "stream_error = true\n" if ($OPT_STREAM_STDOUT);
	printf CONDOR "\n";
	printf CONDOR "+IsExpressQueueJob = True\n";
	printf CONDOR "Rank = IsExpressSlot\n";
	printf CONDOR "Notification = Always\n";
	printf CONDOR "\n";
	printf CONDOR "queue\n";
	close(CONDOR);
	exit(0);
}

open(GETENV, '-|', 'bash', '-c', sprintf('export HOME="$(pwd)"; . /afs/hep.wisc.edu/cms/sw/Xilinx/Vivado/%s/settings64.sh; set', $VIVADO_VERSION));
while (<GETENV>) {
	chomp;
	next unless /^([^=]+)=(.*)$/;
	$ENV{$1} = $2;
}
close(GETENV);

my $OutDir = sprintf("run-%s.%s.%d", $OPT_PROJECT, $OPT_RUN, $OPT_DO_RUN);
unlink($OutDir); # Condor puts a empty temp file here. Screw that.
mkdir($OutDir);

unless ($OPT_STREAM_STDOUT) {
	# If not enabled to condor, direct it to files in the build dir so it's not completely lost.
	close(STDOUT);
	open(STDOUT, '>', "$OutDir/stdout.log");
	close(STDERR);
	open(STDERR, '>', "$OutDir/stderr.log");
}

system('./checkout.pl') and die "Error returned from checkout.pl";

open(VIVADO, '>', sprintf("run-%s.%s.%d.tcl", $OPT_PROJECT, $OPT_RUN, $OPT_DO_RUN));
printf VIVADO "set project \"%s\"\n", $OPT_PROJECT;
printf VIVADO "set run \"%s\"\n", $OPT_RUN;
printf VIVADO "set outdir \"%s\"\n", $OutDir;
printf VIVADO "source condor_pre.tcl\n" if (-f 'condor_pre.tcl');
printf VIVADO <<'EOF';
set_param general.maxThreads 1

if {[get_property IS_IMPLEMENTATION [get_runs $run]]} {
	launch_runs -jobs 1 -to_step write_bitstream [get_runs $run]
} {
	launch_runs -jobs 1 [get_runs $run]
}
wait_on_run [get_runs $run]

foreach {runname} [get_runs] {
	set runlog "[get_property DIRECTORY [get_run $runname]]/runme.log"
	puts "Checking for log from run ${runname}"
	if [file exists $runlog] {
		puts "Copying log from run ${runname}"
		file copy "$runlog" "${outdir}/${runname}.runlog"
	}
}

open_run [get_runs $run]

write_checkpoint -force "${outdir}/${run}.dcp"
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 -input_pins -file "${outdir}/timing.txt"

## This is generated already, just copy the sysdef that has all this crap in it.
#foreach {bd_file} [get_files -filter {FILE_TYPE == "Block Designs"}] {
#	puts "Exporting Block Design ${bd_file}"
#	open_bd_design $bd_file
#	set bd_shortname [file rootname [file tail $bd_file]]
#	file mkdir "${outdir}/${bd_shortname}"
#	export_hardware -dir "${outdir}/${bd_shortname}" $bd_file
#	close_bd_design $bd_shortname
#}

## Generated already as a build product, just copy it rather than regenerating it.
## This'll make things faster, and let modifications to the write_bitstream process function without just crashing us later.
#if {[get_property IS_IMPLEMENTATION [get_runs "$run"]]} {
#	write_bitstream -bin_file "${outdir}/${project}.bit"
#}

set run_dir "[get_property DIRECTORY [get_run ${run}]]"

foreach {bitfile} [glob -nocomplain "${run_dir}/*.bit"] {
	file copy -force "${bitfile}" "${outdir}/[file tail "${bitfile}"]"
}

foreach {binfile} [glob -nocomplain "${run_dir}/*.bin"] {
	file copy -force "${binfile}" "${outdir}/[file tail "${binfile}"]"
}

foreach {sysdef} [glob -nocomplain "${run_dir}/*.sysdef"] {
	set sd_name [file rootname [file tail "${sysdef}"]]
	file mkdir "${outdir}/hdf/${sd_name}"
	file copy -force "${sysdef}" "${outdir}/hdf/${sd_name}/${sd_name}.hdf"
}

foreach {ltx} [glob -nocomplain "${run_dir}/*.ltx"] {
	file mkdir "${outdir}/debug_probes"
	file copy -force "${ltx}" "${outdir}/debug_probes/[file tail "${ltx}"]"
}
EOF
close(VIVADO);

system('vivado', '-mode', 'batch', '-source', sprintf("run-%s.%s.%d.tcl", $OPT_PROJECT, $OPT_RUN, $OPT_DO_RUN), sprintf("workspace/%s/%s.xpr", $OPT_PROJECT, $OPT_PROJECT));

#system('tar', '-cjf', $OutDir.'.tbz2', $OutDir);
