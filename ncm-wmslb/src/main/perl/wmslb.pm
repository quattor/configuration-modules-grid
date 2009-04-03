# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::wmslb;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

use EDG::WP4::CCM::Element qw(unescape);

use LC::File qw(copy);
use LC::Check;
use LC::Process qw(run);

use Encode qw(encode_utf8);

local(*DTA);

# Define paths for convenience. 
my $base = "/software/components/wmslb";
my $glite_config_base = "/system/glite/config";

my $true = "true";
my $false = "false";

my $wmproxy_service_name = 'wmproxy';


##########################################################################
sub Configure {
##########################################################################
  my ($self,$config)=@_;

  my $wmslb_config = $config->getElement($base)->getTree();
  my $envVars;
  if ( defined($wmslb_config->{'env'}) ) {
    $envVars = $wmslb_config->{'env'};
  }
  
  my $services;
  if ( $wmslb_config->{'services'} ) {
    $services = $wmslb_config->{'services'};
  }
  
  # Other initializations
  my $template_dir = "/usr/lib/ncm/config/wmslb";
  my $changes = 0;

  # Check that GLITE_USER and GLITE_GROUP are defined

  my $glite_config = $config->getElement($glite_config_base)->getTree();
  my $config_error = 0;
  unless ( defined($glite_config->{GLITE_USER}) ) {
    $self->error("GLITE_USER undefined");
    $config_error = 1;
  }
  unless ( defined($glite_config->{GLITE_GROUP}) ) {
    $self->error("GLITE_GROUP undefined");
    $config_error = 1;
  }
  unless ( defined($glite_config->{GLITE_LOCATION_VAR}) ) {
    $self->error("GLITE_LOCATION_VAR undefined");
    $config_error = 1;
  }
  if ( $config_error ) {
    return(4);
  }
  
  # Build and update script defining WMS environment.
  # This script is made of a template and all the variables defined in component envVars resource
  
  if ( $wmslb_config->{'envScript'} && $wmslb_config->{'env'} ) {
    my $wms_env_template = $template_dir . "/glite-wms-vars.template";
    my $env_base_content; 
    if ( -f $wms_env_template ) {
      $env_base_content = $self->fill_template($config,$base,$wms_env_template);
      unless ( defined($env_base_content) ) {
        $self->error("Error parsing WMS environment template ($wms_env_template)");
        return(2);
      }
    } else {
      $self->debug(1,"Template ($wms_env_template) not found for ".$wmslb_config->{'envScript'});
      $env_base_content = "#!/bin/sh\n";
    }

    my $env_content = "#!/bin/sh\n" .
                      "# Script built by ncm-wmslb to define WMS/LB environment.\n" .
                      "# DO NOT EDIT.\n\n";
    $env_content .= $env_base_content;
  
    if ( %$envVars ) {
      $env_content .= "\n# gLite WMS parameters\n";
      for my $variable (keys(%$envVars)) {
        if ( length(ref($envVars->{$variable})) eq 0 ) {       
          if ( defined($envVars->{$variable}) ) {
            $env_content .= "export $variable=".$envVars->{$variable}."\n"; 
          } else {
            $self->warn("Value of variable $variable undefined. Ignoring it.");
          }
        } else {
          $self->error("Value of variable $variable must be a string or a number.");            
        }
      }
      
      $changes = LC::Check::file(
                                 $wmslb_config->{'envScript'},
                                 backup   => ".old",
                                 contents => encode_utf8($env_content),
                            );
      if ( $changes < 0 ) {
        $self->error("Error updating environment script (".$wmslb_config->{'envScript'}.")");
        return(1);
      }
    }
    
  } else {
    $self->debug(1,"Environment script file name not defined. Skipping it.");
  }


  # Build WMS configuration file.
  # This file has one section per service. For each service, there is a separate template.
  # At the beginning of the configuration file, add the content of prologue template.
  
  if ( defined($services) ) {
    $self->info("Checking common configuration file (".$wmslb_config->{'confFile'}.")...");  

    my $conf_content = "[\n";
    
    my $prologue_template = $template_dir . '/prologue.template';
    my $prologue_content;
    if ( -f $prologue_template) {
      $prologue_content = $self->formatConfSection('Common',$config,$base.'/common',$prologue_template);
      if ( defined($prologue_content) ) {
        $conf_content .= $prologue_content;
      } else {
        $self->warning("Error parsing WMS configuration file template ($prologue_template).");
      }
    } else {
      $self->debug(1,"No template found for configuration file prologue.");
    }
  
    for my $service (keys(%$services)) {
      my $service_template = $template_dir . '/' . $service . '.template';
      my $service_conf_content = '';
      if ( -f $service_template ) {
        $self->debug(1,"Parsing template $service_template for configuration file $service section.");
        $service_conf_content = $self->formatConfSection($services->{$service}->{name},
                                                         $config,
                                                         $base.'/services/'.$service.'/options',
                                                         $service_template);
        if ( defined($service_conf_content) ) {
          $conf_content .= $service_conf_content;
        } else {
          $self->warning("Error parsing WMS configuration file template ($service_template).");
        }
      } else {
        $self->debug(1,"No template found for configuration file $service section.");
      }
    }
    
    $conf_content .= "\n];\n";
  
    $changes = LC::Check::file(
                               $wmslb_config->{'confFile'},
                               backup   => ".old",
                               contents => encode_utf8($conf_content),
                          );
    if ( $changes < 0 ) {
      $self->error("Error updating configuration file (".$wmslb_config->{'confFile'}.")");
      return(1);
    }

  }

  # Build service specific configuration files if any
  
  for my $service (keys(%$services)) {
    if ( $services->{$service}->{confFiles} ) {
      my $confFiles = $services->{$service}->{confFiles};
      for my $confFile (keys(%$confFiles)) {
        my $confFileTemplate = $template_dir . '/' . $confFiles->{$confFile}->{template};
        $confFile = unescape($confFile);
        $self->info("Checking service $service configuration file $confFile...");
        unless ( -f $confFileTemplate ) {
          $self->error("Template for configuration file not found ($confFileTemplate)");
          next;
        }
        my $confFileContent = $self->fill_template($config,$base.'/services/'.$service.'/options',$confFileTemplate);     
        unless ( defined($confFileContent) ) {
          $self->error("Error parsing configuration file template ($confFileTemplate)");
          next;
        }   
        $changes = LC::Check::file(
                                   $confFile,
                                   backup   => ".old",
                                   contents => encode_utf8($confFileContent),
                              );
        if ( $changes < 0 ) {
          $self->error("Error updating configuration file ($confFile)");
          next;
        }
      }
      
    }

    # For WMProxy service, build Load Monitor script.
    # If script content is explicitly set, update the script if needed.
    # Else build the script from the template, if the script doesn't exist.
    # Also check if the WMProxy must be drained.
    
    if ( $service eq $wmproxy_service_name ) {
      my $script_config = $services->{$service}->{LoadMonitorScript};
      if ( $script_config->{contents} ) {
        $self->info("Checking WM Load Monitor script ($script_config->{name})");
        $changes = LC::Check::file($script_config->{name},
                                   backup   => ".old",
                                   contents => encode_utf8($script_config->{contents}),
                                   mode => 0755,
                                  );
        if ( $changes < 0 ) {
          $self->error("Error updating WM Load Monitor script ($script_config->{name})");
          next;
        }
        
      } else {
        if ( !-f $script_config->{name} ) {
          $self->info("Creating WM Load Monitor script ($script_config->{name}) from template ($script_config->{template})");
          $changes = LC::Check::file($script_config->{name},
                                     source   => $script_config->{template},
                                     mode => 0755,
                                    );
          if ( $changes < 0 ) {
            $self->error("Error creating WM Load Monitor script from template ($script_config->{name})");
          }            
        }          
      }
      
      # Check if the WMProxy must be drained and do appropriate actions
      my $drain_file = $glite_config->{GLITE_LOCATION_VAR} . '/.drain';
      if ( $services->{$service}->{drained} ) {
        $self->info('Draining WMProxy...');
        my $contents = "<gacl>\n  <entry>\n    <any-user/>\n    <deny><exec/></deny>\n  </entry>\n</gacl>";
        $changes = LC::Check::file($drain_file,
                                   contents   => $contents,
                                   mode => 0755,
                                  );
        if ( $changes < 0 ) {
          $self->error("Error creating WMProxy drain file ($drain_file)");
        }                    
      } else {
        if ( -f $drain_file ) {
          $self->info('Enabling WMProxy...');
          unlink $drain_file;
        }
      }
    }
  }

  # Create working directories for each configured service
  
  for my $service (keys(%$services)) {
    my $workDirs = $services->{$service}->{workDirs};
    if ( $workDirs ) {
      $self->info("Checking working directories for service $service (".join(',',@$workDirs).")");
      for my $directory (@$workDirs) {
        if ( $directory !~ /^\// ) {
          if ( $wmslb_config->{workDirDefaultParent} ) {
            $directory = $wmslb_config->{workDirDefaultParent} . '/' . $directory;            
          } else {
            $self->error("No default parent defined for working directory '$directory'");
            next;
          }
        }
        $self->debug(1,"Checking directory $directory...");
        $changes = LC::Check::directory($directory,
                                       );
        if ( $changes < 0 ) {
          $self->error("Error creating directory $directory");
        }
        $changes = LC::Check::status($directory,
                                     mode => 0755,
                                     owner => $glite_config->{GLITE_USER},
                                     group => $glite_config->{GLITE_GROUP},
                                    );
        if ( $changes < 0 ) {
          $self->error("Error setting owner/perms on directory $directory");
        }
      }
    }
  }
  
  
  return;
}


# Method to read, parse and format a WMS configuration file section template
#
# Return value :
#   parsed section or undef in case of error

sub formatConfSection {
  my $function_name = 'formatConfTemplate';
  my ($self, $service, $config, $base, $template) = @_;
  unless ( defined($service) ) {
    $self->error($function_name.":Missing required argument : service name");
  }
  unless ( defined($config) ) {
    $self->error($function_name.":Missing required argument : NCM configuration");
  }
  unless ( defined($base) ) {
    $self->error($function_name.":Missing required argument : configuration path");
  }
  unless ( defined($template) ) {
    $self->error($function_name.":Missing required argument : template name");
  }

  if ( -f $template) {
    my $temp = $self->fill_template($config,$base,$template);
    if ( defined($temp) ) {
      my @content = split /[\r\n]+/, $temp;
      my $section_content = "   $service = [\n";
      for (@content) {
        $section_content .= "      $_\n";      
      }
      $section_content .= "   ];\n";
      return($section_content);
    } else {
      $self->warning("Error parsing WMS configuration file template ($template).");
      return (undef);
    }
  } else {
    $self->error("No template found for configuration file section ($service).");
    return (undef);
  }

  return(undef);
}


# Do a simple template substitution.  The following tags are recognized:
#
# <%path|default%>
# <%"path|default"%>
#
# For paths which don't exist the given default value is used.  However,
# if the path doesn't exist and the default is not specified, then the
# line is not printed at all.  The only difference between the first and
# second forms is that the second will create a double-quoted string with
# any embedded double quotes properly escaped. 
#
sub fill_template {
  my $function_name = 'fill_template';
  my ($self, $config, $base, $template) = @_;
  unless ( defined($config) ) {
    $self->error($function_name.":Missing required argument : NCM configuration");
  }
  unless ( defined($base) ) {
    $self->error($function_name.":Missing required argument : configuration path");
  }
  unless ( defined($template) ) {
    $self->error($function_name.":Missing required argument : template file");
  }

  my $translation = "";

  if (-e "$template") {
    open TMP, "<$template";
    while (<TMP>) {
      my $err = 0;
  
      # Special form for date.
      s/<%!date!%>/localtime()/eg;
  
      # Need quoted result (escape embedded quotes).
      s!<%"\s*(/[\w/]+)\s*(?:\|\s*(.+?))?\s*"%>!self->quote($self->fill($config,$1,$2,\$err))!eg;
      s!<%"\s*([\w]+[\w/]*)(?:\|\s*(.+?))?\s*"%>!$self->quote($self->fill($config,"$base/$1",$2,\$err))!eg;
  
      # Normal result OK. 
      s!<%\s*(/[\w/]+)\s*(?:\|\s*(.+?))?%>!$self->fill($config,$1,$2,\$err)!eg;
      s!<%\s*([\w]+[\w/]*)\s*(?:\|\s*(.+?))?%>!$self->fill($config,"$base/$1",$2,\$err)!eg;
  
      # Add the output line unless an error was signaled.  An
      # error occurs when an element doesn't exist.  In this
      # case it is assumed that the value is optional and the
      # line is omitted.  
      $translation .= $_ unless $err;
    }
    close TMP;
  } else {
    $self->warn("$function_name: template file not found ($template)");
    $translation = undef;
  }

  return $translation;
}


# Escape quotes in a string value.
sub fill {
    my ($self,$config,$path,$default,$errorRef) = @_;

    my $value = "";

    if ($config->elementExists($path)) {
        $value = $config->getValue($path);
    } elsif (defined $default) {
        $value = $default;
    } else {
        # Flag an error and return empty string.
        $$errorRef = "1";
    }
    return $value;
}


# Escape quotes and double quote the value. 
sub quote {
    my ($self,$value) = @_;

    $value =~ s/"/\\"/g;  # escape any embedded quotes
    $value = '"'.$value.'"';
    return $value;
}


1; #required for Perl modules

