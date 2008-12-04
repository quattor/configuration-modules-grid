# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::apel;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

use File::Path;
use File::Basename;

use EDG::WP4::CCM::Element;

##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    my %cfiles = ();

    # Define path for convenience. 
    my $base = "/software/components/apel";

    # Loop over all of the files.  (Each key is the encoded file name.)
    if ($config->elementExists("$base/configFiles")) {
	my $fileElement = $config->getElement("$base/configFiles");
	while ($fileElement->hasNextElement()) {
	    my $element = $fileElement->getNextElement();
	    my $name = unescape($element->getName());
	    my $path = "$base/configFiles/" . ($element->getName());
	    my $contents = $self->createContents($config,$path);
	    if (defined($contents)) {

		# Ensure that the directory exists.
		my $dir = dirname($name);
		unless (-d $dir) {
		    mkpath($dir, 0, 0755);
		}
		unless (-d $dir) {
		    $self->error("can't create directory ($dir)");
		    next;
		}

		# Write out the file.  This contains a database password.
		# Ensure that the file is created with only user read and
		# write access.
		my $oumask = umask;
		umask(0177);
		open CONFIG, ">", "$name";
		print CONFIG $contents;
		close CONFIG;
		$self->info("updated $name");
		umask($oumask);
	    }
	}
    }

    return 1;
}

#
# create the contents of a configuration file from an
# element reference
#
sub createContents {
    my ($self, $config, $path) = @_;

    # Collect the basic information. 
    my $base = "$path";

    my $enableDebugLogging = 'no';
	my $inspectTables = 'no';
	
    if ($config->elementExists("$path/enableDebugLogging")) {
		$enableDebugLogging = $config->getValue("$path/enableDebugLogging");
    }
	if ($config->elementExists("$path/inspectTables")) {
		$inspectTables = $config->getValue("$path/inspectTables");
	}
    my $dbURL = $config->getValue("$path/DBURL");
    my $dbUser = $config->getValue("$path/DBUsername");
    my $dbPass = $config->getValue("$path/DBPassword");
    my $siteName = $config->getValue("$path/SiteName");

    # Write the header and the basic information to the contents. 
    my $contents = <<"EOF"
<?xml version="1.0" encoding="UTF-8"?>
<ApelConfiguration enableDebugLogging="$enableDebugLogging">
  <DBURL>$dbURL</DBURL>
  <DBUsername>$dbUser</DBUsername>
  <DBPassword>$dbPass</DBPassword>
  <SiteName>$siteName</SiteName>
EOF
;

    # Check for the DBDeleteProcessor.
    $base = "$path/DBDeleteProcessor";
    if ($config->elementExists($base)) {
	if ($config->elementExists("$base/cleanAll")) {
	    my $opt = $config->getValue("$base/cleanAll"); 
	    $contents .= "  <DBDeleteProcessor cleanAll=\"$opt\"/>\n";
	} else {
	    $contents .= "  <DBDeleteProcessor/>\n";
	}
    }

	# Check if we have to inspect tables
	if ($inspectTables eq "yes") {
		$contents .= "  <DBProcessor inspectTables=\"yes\"/>\n";
	}

    # Check for the CPUProcessor.
    $base = "$path/CPUProcessor";
    if ($config->elementExists($base)) {
	$contents .= "  <CPUProcessor>\n";

	if ($config->elementExists("$base/GIIS")) {
	    my $opt = $config->getValue("$base/GIIS");
	    $contents .= "    <GIIS>$opt</GIIS>\n";
	}

	if ($config->elementExists("$base/DefaultCPUSpec")) {
	    my $opt = $config->getValue("$base/DefaultCPUSpec");
	    $contents .= "    <DefaultCPUSpec>$opt</DefaultCPUSpec>\n";
	}

	$contents .= "  </CPUProcessor>\n";
    }

    # Check for the EventLogProcessor.
    $base = "$path/EventLogProcessor";
    if ($config->elementExists($base)) {

	$contents .= "  <EventLogProcessor>\n";

	my $opt1 = '';
	if ($config->elementExists("$base/searchSubDirs")) {
	    $opt1 = $config->getValue("$base/searchSubDirs");
	    $opt1 = "searchSubDirs=\"$opt1\"";
	}

	my $opt2 = '';
	if ($config->elementExists("$base/reprocess")) {
	    $opt2 = $config->getValue("$base/reprocess");
	    $opt2 = "reprocess=\"$opt2\"";
	}

	$contents .= "    <Logs $opt1 $opt2>\n";

	if ($config->elementExists("$base/Dir")) {
	    my $opt = $config->getValue("$base/Dir");
	    $contents .= "      <Dir>$opt</Dir>\n";
	}

	if ($config->elementExists("$base/ExtraFile")) {
	    my $list = $config->getElement("$base/ExtraFile");
	    while ($list->hasNextElement()) {
		my $prop = $list->getNextElement();
		my $opt = $prop->getValue();
		$contents .= "      <ExtraFile>$opt</ExtraFile>\n";
	    }
	}

	$contents .= "    </Logs>\n";

	if ($config->elementExists("$base/Timezone")) {
	    my $opt = $config->getValue("$base/Timezone");
	    $contents .= "    <Timezone>$opt</Timezone>\n";
	}

	$contents .= "  </EventLogProcessor>\n";
    }

    # Check for the GKLogProcessor.
    $base = "$path/GKLogProcessor";
    if ($config->elementExists($base)) {

	$contents .= "  <GKLogProcessor>\n";

	if ($config->elementExists("$base/SubmitHost")) {
	    my $opt = $config->getValue("$base/SubmitHost");
	    $contents .= "    <SubmitHost>$opt</SubmitHost>\n";
	}

	my $opt1 = '';
	if ($config->elementExists("$base/searchSubDirs")) {
	    $opt1 = $config->getValue("$base/searchSubDirs");
	    $opt1 = "searchSubDirs=\"$opt1\"";
	}

	my $opt2 = '';
	if ($config->elementExists("$base/reprocess")) {
	    $opt2 = $config->getValue("$base/reprocess");
	    $opt2 = "reprocess=\"$opt2\"";
	}

	$contents .= "    <Logs $opt1 $opt2>\n";

	if ($config->elementExists("$base/GKLogs")) {
	    $contents .= "      <GKLogs>\n";

	    my $list = $config->getElement("$base/GKLogs");
	    while ($list->hasNextElement()) {
		my $prop = $list->getNextElement();
		my $opt = $prop->getValue();
		$contents .= "        <Dir>$opt</Dir>\n";
	    }
	    $contents .= "      </GKLogs>\n";
	}

	if ($config->elementExists("$base/MessageLogs")) {
	    $contents .= "      <MessageLogs>\n";

	    my $list = $config->getElement("$base/MessageLogs");
	    while ($list->hasNextElement()) {
		my $prop = $list->getNextElement();
		my $opt = $prop->getValue();
		$contents .= "        <Dir>$opt</Dir>\n";
	    }
	    $contents .= "      </MessageLogs>\n";
	}

	$contents .= "    </Logs>\n";

	$contents .= "  </GKLogProcessor>\n";
    }

    # Check for the BlahdLogProcessor.
    $base = "$path/BlahdLogProcessor";
    if ($config->elementExists($base)) {

	$contents .= "  <BlahdLogProcessor>\n";

	#setup submithost
	if ($config->elementExists("$base/SubmitHost")) {
	    my $opt = $config->getValue("$base/SubmitHost");
	    $contents .= "    <SubmitHost>$opt</SubmitHost>\n";
	}

	#setup BlahdLogPrefix
	my $opt_path;
	$opt_path="$base/BlahdLogPrefix";
	if ($config->elementExists("$opt_path")) {
	    $contents .= "    <BlahdLogPrefix>" . $config->getValue("$opt_path") . "</BlahdLogPrefix>\n";
	}

	#setup Logs directories
	my $opt1 = '';
	if ($config->elementExists("$base/searchSubDirs")) {
	    $opt1 = $config->getValue("$base/searchSubDirs");
	    $opt1 = "searchSubDirs=\"$opt1\"";
	}

	my $opt2 = '';
	if ($config->elementExists("$base/reprocess")) {
	    $opt2 = $config->getValue("$base/reprocess");
	    $opt2 = "reprocess=\"$opt2\"";
	}

	if ($config->elementExists("$base/BlahdLogDir")) {
	    $contents .= "    <Logs $opt1 $opt2>\n";
	    my $list = $config->getElement("$base/BlahdLogDir");
	    while ($list->hasNextElement()) {
		my $prop = $list->getNextElement();
		my $opt = $prop->getValue();
		$contents .= "        <Dir>$opt</Dir>\n";
	    }
	    $contents .= "    </Logs>\n";
	}

	#finish
	$contents .= "  </BlahdLogProcessor>\n";
    }

    # Check for the JoinProcessor.
    $base = "$path/JoinProcessor";
    if ($config->elementExists($base)) {

	my $opt = '';
	if ($config->elementExists("$base/publishGlobalUserName")) {
	    $opt = $config->getValue("$base/publishGlobalUserName");
	    $opt = " publishGlobalUserName=\"$opt\"";
	}

	$contents .= "  <JoinProcessor$opt>\n";

	if ($config->elementExists("$base/Republish")) {
	    my $opt = $config->getValue("$base/Republish");
	    $contents .= "    <Republish>$opt</Republish>\n";
	}

	$contents .= "  </JoinProcessor>\n";
    }

    # Write out the end of the configuration. 
    $contents .= <<"EOF"
</ApelConfiguration>
EOF
;

    return($contents);
};



#
# small helper function for unescaping chars
#
sub unescape ($) {
  my $str=shift;
  $str =~ s!(_[0-9a-f]{2})!sprintf("%c",hex($1))!eg;
  return $str;
}



1;      # Required for PERL modules

