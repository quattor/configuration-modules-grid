# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::gold;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

$EC->error_handler(\&my_handler);
sub my_handler {
    my($ec, $e) = @_;
    $e->has_been_reported(1);
}

use EDG::WP4::CCM::Element;

use File::Copy;
use File::Path;
use Encode qw(encode_utf8);

use constant CLIENT_CONFIG_INT => qw(
    server.port
    response.chunksize
    currency.precision
    log4perl.appender.Log.size
    log4perl.appender.Log.max
);

use constant CLIENT_CONFIG_STR => qw(
    server.host
    server.backup
    security.authentication
    security.encryption
    security.token.type
    wire.protocol
    response.chunking
    account.show
    allocation.show
    balance.show
    job.show
    machine.show
    project.show
    quotations.show
    reservation.show
    transaction.show
    user.show
    log4perl.logger
    log4perl.appender.Log.Threshold
    log4perl.appender.Screen.Threshold
    log4perl.logger.Message
    log4perl.appender.Log
    log4perl.appender.Log.filename
    log4perl.appender.Log.mode
    log4perl.appender.Log.layout
    log4perl.appender.Log.layout.ConversionPattern
    log4perl.appender.Screen
    log4perl.appender.Screen.layout
    log4perl.appender.Screen.layout.ConversionPattern
);


use constant CGICLIENT_CONFIG_INT => qw(
    server.port
    response.chunksize
    currency.precision
    log4perl.appender.Log.size
    log4perl.appender.Log.max
);

use constant CGICLIENT_CONFIG_STR => qw(
    server.host
    server.backup
    security.authentication
    security.encryption
    security.token.type
    response.chunking
    log4perl.logger
    log4perl.appender.Log.Threshold
    log4perl.appender.Screen.Threshold
    log4perl.logger.Message
    log4perl.appender.Log
    log4perl.appender.Log.filename
    log4perl.appender.Log.mode
    log4perl.appender.Log.layout
    log4perl.appender.Log.layout.ConversionPattern
    log4perl.appender.Screen
    log4perl.appender.Screen.layout
    log4perl.appender.Screen.layout.ConversionPattern
);


use constant SERVER_CONFIG_INT => qw(
    server.port
    response.chunksize
    currency.precision
    log4perl.appender.Log.size
    log4perl.appender.Log.max
);

use constant SERVER_CONFIG_STR => qw(
    super.user
    server.host
    database.datasource
    database.user
    database.password
    security.authentication
    security.encryption
    account.autogen
    allocation.autogen
    machine.autogen
    machine.default
    project.autogen
    project.default
    user.autogen
    user.default
    log4perl.logger
    log4perl.appender.Log.Threshold
    log4perl.appender.Screen.Threshold
    log4perl.logger.Message
    log4perl.appender.Log
    log4perl.appender.Log.filename
    log4perl.appender.Log.mode
    log4perl.appender.Log.layout
    log4perl.appender.Log.layout.ConversionPattern
    log4perl.appender.Screen
    log4perl.appender.Screen.layout
    log4perl.appender.Screen.layout.ConversionPattern
);



##########################################################################
sub Configure($$@) {
##########################################################################
    
    our ($self, $config) = @_;

    # Define paths for convenience. 
    my $base = "/software/components/gold";

    our $tree;
    my ($contents,$result,$fname);
    my @alloptions;

    ## default config path
    my $cpath = "/usr/local/gold/etc";
    if ($config->elementExists("$base/configPath")) {
        $cpath = $config->getValue("$base/configPath");
    }

    mkpath($cpath, 0, 0755) unless (-e $cpath);
    if (! -d $cpath) {
        $self->Fail("Can't create directory: $cpath");
        return 1;
    }

    ##
    ## start with auth_key file
    ## -r--r-----. 1 root apache   xxx auth_key
    $fname = "$cpath/auth_key";
    if ($config->elementExists("$base/auth_key")) {
	$contents = $config->getElement($base."/auth_key")->getValue();
    } else {
        $self->Fail("mandatory auth_key missing");
        return 1;
    }

    $result = LC::Check::file( $fname,
                                  contents => encode_utf8($contents),
                                  owner       => 'root',
                                  group       => 'apache',
                                  mode        => 0440,
                                );
    if ($result) {
        $self->log("$fname updated");
    } else {
        if (!defined($result)) {
            $self->error("$fname update failed");
            return 1;
        }
    }


    ## 
    ## client config
    ## -rw-r--r--. 1 root root xxx gold.conf
    ##    
    $fname = "$cpath/gold.conf";

    $tree = $config->getElement($base."/client")->getTree();
    $contents = '';

    @alloptions=();
    push(@alloptions,CLIENT_CONFIG_INT,CLIENT_CONFIG_STR);
    foreach my $opt (keys(%$tree)) {
        $self->warn("Unknown client opt $opt in tree") if (! (grep {$_ eq $opt} @alloptions ));
    }

    $contents.=get_cfg("string",CLIENT_CONFIG_INT);    
    $contents.=get_cfg("string",CLIENT_CONFIG_STR);    

    $result = LC::Check::file( $fname,
                                  contents => encode_utf8($contents),
                                  owner       => 'root',
                                  group       => 'root',
                                  mode        => 0644,
                                );
    if ($result) {
        $self->info("$fname updated");
    } else {
        if (!defined($result)) {
            $self->error("$fname update failed");
            return 1;
        }
    }


    ## 
    ## cgiclient config
    ## -rw-r--r--. 1 root root xxx goldg.conf
    ##    
    if ($config->elementExists("$base/cgiclient")) {
	$fname = "$cpath/goldg.conf";

	$tree = $config->getElement($base."/cgiclient")->getTree();
	$contents = '';

	@alloptions=();
	push(@alloptions,CGICLIENT_CONFIG_INT,CGICLIENT_CONFIG_STR);
	foreach my $opt (keys(%$tree)) {
	    $self->warn("Unknown cgiclient opt $opt in tree") if (! (grep {$_ eq $opt} @alloptions ));
	}

	$contents.=get_cfg("string",CGICLIENT_CONFIG_INT);    
	$contents.=get_cfg("string",CGICLIENT_CONFIG_STR);    

	$result = LC::Check::file( $fname,
                                  contents => encode_utf8($contents),
                                  owner       => 'root',
                                  group       => 'root',
                                  mode        => 0644,
                                );
	if ($result) {
	    $self->info("$fname updated");
	} else {
	    if (!defined($result)) {
		$self->error("$fname update failed");
		return 1;
	    }
	}
    }
    


    ## 
    ## server config
    ## -rw-------. 1 root root xxx goldd.conf
    ## 
    if ($config->elementExists("$base/server")) {
        $fname = "$cpath/goldd.conf";
    
        $tree = $config->getElement($base."/server")->getTree();
        $contents = '';

        @alloptions=();
        push(@alloptions,SERVER_CONFIG_INT,SERVER_CONFIG_STR);
        foreach my $opt (keys(%$tree)) {
            $self->warn("Unknown client opt $opt in tree") if (! (grep {$_ eq $opt} @alloptions ));
        }
    
        $contents.=get_cfg("string",SERVER_CONFIG_INT);    
        $contents.=get_cfg("string",SERVER_CONFIG_STR);    

    
        $result = LC::Check::file( $fname,
                                      contents => encode_utf8($contents),
                                      owner       => 'root',
                                      group       => 'root',
                                      mode        => 0600,
                                    );
	
        if ($result) {
            $self->info("$fname updated. restarting service");
            restartgold();
        } else {
            if (!defined($result)) {
                $self->error("$fname update failed");
                return 1;
            }
        }
    }

## restart gold
sub restartgold {
    my $serv = shift|| "gold";
    
    ## new style
    my $output;
    if(LC::Process::execute(["service",$serv,"restart"],
                            "stdout" => \$output,
                            "stderr" => "stdout"
    ) && ($? == 0)) {
        $self->debug(4,"runrun succesfully ran \"service $serv restart\"");
        return 0;
    } else {
        $self->error("runrun failed to run \"service $serv restart\": output $output");
        return 1;
    }
}

sub get_cfg {
    my $mod = shift;
    ## options
    my @options = @_;

    my $c = '';
    my ($ans,$opt);

    foreach $opt (@options) {
        next if (!exists($tree->{$opt}));

        my $val='';
        my $ref=$tree->{$opt};
        if (ref($ref) eq "ARRAY") {
            $val=join(",",@$ref);
        } else {
            $val=$ref;
        }

        if ($mod eq "string") {
            $ans = "$val";
        } elsif ($mod eq "boolean") {
            $ans = "off";
            $ans = "on" if ($val);
        } elsif ($mod eq "quoted") {
            $ans = "'$val'";
        } else {
            $self->error("get_cfg: Unknown mode $mod");
        }; 

        $c .= "$opt = ".$ans."\n";
    }
    $c .= "\n";
    
    return $c;
}


## real end
    return 1;
}


1;      # Required for PERL modules
