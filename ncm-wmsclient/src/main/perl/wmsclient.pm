# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::wmsclient;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;
use File::Copy;
use File::Path;
use LC::File qw(file_contents);

# In the following hash, the same keys must exist.
#   - mw_locations : define install path of the corresponding MW
#   - mw_config_opts : define relative configuration path (inside this component config)
#                      of options related to the corresponding MW
#   - wms_hosts_config : define relative configuration path under /system/vo/VONAME 
#                        of RB/WMS hosts used by the corresponding version of the MW
#                        (empty string means in /system/vo/VONAME).
#
# Supported MW variants are :
#  - edg : EDG RB
#  - glite : first generation of gLite WMS (LB/NS interface)
#  - wmproxy : gLite WMS with a WMProxy interface
 
my %mw_config_dir_defaults = (
                              "edg" => "/opt/edg/etc",
                              "glite" => "/opt/glite/etc",
                              "wmproxy" => "/opt/glite/etc",
                             );

# Per-VO configuration file used by submission tools. Can be a list to
# accomodate the regular changes in the tools!  
# In particular in gLite 3.2, support for WMS 3.0 was completely removed and
# the name used by "glite" variant was reused by WMS 3.2. In 3.1, the name
# was different to avoid clashed (file content is not the same).                      
my %mw_vo_config_file_defaults = (
                              "edg" => ["edg_wl_ui.conf"],
                              "glite" => ["glite_wmsui.conf"],
                              "wmproxy" => ["glite_wmsui.conf","glite_wms.conf"],
                             );
# cmd/gui_classads variables are used to define where to put
# the configuration for Python-based utilities. In WMS 3.0 ("glite" variant)
# and WMS 3.1 (first version of "wmproxy" variant), the glite_wmsui_cmd_var.conf file
# used to be part of the RPM but this is no longer the case in 3.2 so build it
# for "wmproxy" variant. 
my %mw_cmd_classads_defaults_file = (
                               "edg", "edg_wl_ui_cmd_var.conf",
                               "glite", undef,
                               "wmproxy", "glite_wmsui_cmd_var.conf",
                              );
my %mw_cmd_classads_defaults_template = (
                                      "edg", "cmd-classads.template",
                                      "glite", "cmd-classads.template",
                                      "wmproxy", "cmd-classads.template",
                                     );
my %mw_gui_classads_defaults_file = (
                               "edg", "edg_wl_ui_gui_var.conf",
                               "glite", "glite_wmsui_gui_var.conf",
                               "wmproxy", undef,
                              );
my %mw_gui_classads_defaults_template = (
                                      "edg", "gui-classads.template",
                                      "glite", "gui-classads.template",
                                      "wmproxy", undef,
                                     );

my %mw_install_dir_config = (
                             "edg" => "/system/edg/config/EDG_LOCATION",
                             "glite" => "/system/edg/config/GLITE_LOCATION",
                             "wmproxy" => "/system/edg/config/GLITE_LOCATION",
                            );
                        
my %mw_config_opts = (
                      "edg" => "edg",
                      "glite" => "glite",
                      "wmproxy" => "wmproxy",
                     );
                     
my %wms_hosts_config = (
                        "edg" => undef,
                        "glite" => "wms",
                        "wmproxy" => "wms",
                       );
my %mw_config;


##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    # Define paths for convenience. 
    my $base = "/software/components/wmsclient";
    my $vobase = "/system/vo";
    my $template_dir = "/usr/lib/ncm/config/wmsclient";

    # Retrieve UI config for each MW variant and set defaults
    for my $mw_variant (sort(keys(%mw_config_opts))) {
      my $conf_path = $base.'/'.$mw_config_opts{$mw_variant};
      if ( $config->elementExists($conf_path) ) {
        $mw_config{$mw_variant} = $config->getElement($conf_path)->getTree();
      }
      if ( defined($mw_config{$mw_variant}) ) {
        $self->debug(1, "$mw_variant UI : active flag=$mw_config{$mw_variant}->{active}");
      } else {
        $self->debug(1, "$mw_variant UI : no configuration found");
      }

        
      # Default location of MW config files.
      if ( ! defined($mw_config{$mw_variant}->{configDir}) ) {
        if ( $config->elementExists($mw_install_dir_config{$mw_variant}) ) {
          $mw_config{$mw_variant}->{configDir} = 
                                     $config->getElement($mw_install_dir_config{$mw_variant})->getValue() . '/etc';
        } else {
          $mw_config{$mw_variant}->{configDir} = $mw_config_dir_defaults{$mw_variant};            
        }
      }  
    }


    # Retrieve VO configs
    my %vo_config;
    if ($config->elementExists("$vobase")) {
      %vo_config = %{$config->getElement("$vobase")->getTree()};
    } else {
      self->error('No VO configured on this system');
      return(2);
    }
    
    
    
    # Configure each MW variant marked as active (present in mw_config).
    # There is one config file per VO.
    
    for my $mw_variant (sort(keys(%mw_config))) {
      if ( !$mw_config{$mw_variant}->{active} ) {
        $self->debug(1,"$mw_variant UI configuration present but inactive. Ignoring.");
        next; 
      }
      
      $self->info("Checking $mw_variant UI configuration...");
      
      my $fname;
      my $result;
      my $template;
      my $template_config = $base.'/'.$mw_variant;
      
      # First configure default attributes for all VO (cmd and gui variants)
      # Do it unconditionnally (as it will be put also into the VO specific file)
      # but write the file only if defined.
      my $default_contents;
      if ( defined($mw_cmd_classads_defaults_template{$mw_variant}) ) {
        $template = $template_dir.'/'.$mw_cmd_classads_defaults_template{$mw_variant};
        $default_contents = $self->fill_template($config,
                                                    $template_config."/defaultAttrs",
                                                    $template);
        if ( defined($default_contents) ) {
          if ( defined($mw_cmd_classads_defaults_file{$mw_variant}) ) {
            $fname = $mw_config{$mw_variant}->{configDir}.'/'.$mw_cmd_classads_defaults_file{$mw_variant};
            my $contents = "[\n". $default_contents . "\n]\n"; 
            $result = $self->updateConfigFile($fname,$contents);
            if ( $result ) {
              $self->log("$fname updated");
            } else {
              $self->debug(1,"Default cmd ClassAds for $mw_variant UI ($fname) up-to-date");
            };
          }
        } else {
          $self->error("Error building cmd ClassAds defaults for $mw_variant UI");
        }
      }
      if ( !defined($default_contents) ) {
        $default_contents = '';
      }

      if ( defined($mw_gui_classads_defaults_template{$mw_variant}) ) {
        $template = $template_dir.'/'.$mw_gui_classads_defaults_template{$mw_variant};
        my $gui_contents = $self->fill_template($config,
                                             $template_config."/defaultAttrs",
                                             $template);
        if ( defined($gui_contents) ) {
          if ( defined($mw_gui_classads_defaults_file{$mw_variant}) ) {
            $fname = $mw_config{$mw_variant}->{configDir}.'/'.$mw_gui_classads_defaults_file{$mw_variant}; 
            my $contents = "[\n". $gui_contents . "\n]\n"; 
            $result = $self->updateConfigFile($fname,$contents);
            if ( $result ) {
              $self->log("$fname updated");
            } else {
              $self->debug(1,"Default gui ClassAds for $mw_variant UI ($fname) up-to-date");
            };
          }
        } else {
          $self->error("Error building gui ClassAds defaults for $mw_variant UI");
        }
      }
    
      # EDG UI config is under /system/vo/VONAME, config for other UI variants is under
      # /system/vo/VONAME/$wms_hosts_config{$mw_variant}
      my %ui_config;
      for my $vo (sort(keys(%vo_config))) {
        $self->debug(1,"Configuring $mw_variant UI for VO $vo");
        
        if ( defined($wms_hosts_config{$mw_variant}) ) {
          unless ( defined($vo_config{$vo}->{services}->{$wms_hosts_config{$mw_variant}}) ) {
            $self->info("VO $vo : no information found for $mw_variant UI");
            next;
          }
          $self->debug(2,"Using information in $vobase/$vo/$wms_hosts_config{$mw_variant}");
          %ui_config = %{$vo_config{$vo}->{services}->{$wms_hosts_config{$mw_variant}}};
        } else {
          $self->debug(2,"Using information in $vobase/$vo");
          %ui_config = %{$vo_config{$vo}->{services}};
        }
        my $prop_list = join ",", sort(keys(%ui_config));
        $self->debug(2,"VO information available properties : $prop_list");

        # Check at least LB host and NS (EDG RB) or WMProxy (gLite WMS) information is present.
        # Else ignore VO for this MW variant.
        # If MyProxy is not defined for a VO, configure the VO but issue a warning.
        # HDR is optional.
        unless ( defined($ui_config{lbhosts}) || ($mw_variant eq 'wmproxy') ) {
          $self->warn("$mw_variant UI : no LB defined for VO $vo. No configuration done");
          next;
        }
        unless ( defined($ui_config{nshosts}) || ($mw_variant eq 'wmproxy') ) {
          $self->warn("$mw_variant UI : No NS defined for VO $vo. No configuration done");
        }
        if ( $mw_variant eq 'wmproxy' ) {
          unless ( defined($ui_config{wmproxies}) ) {
            $self->warn("$mw_variant UI : No WMProxy defined for VO $vo. No configuration done");          
          }
          $ui_config{lbhosts} = undef;
          $ui_config{nshosts} = undef;
        } else {
          $ui_config{wmproxies} = undef;
        }
        
        my $myproxy; 
        if ( defined($vo_config{$vo}->{services}->{myproxy}) ) {
          $myproxy = $vo_config{$vo}->{services}->{myproxy};          
        } else {
          $self->info('No MyProxy server defined for VO '.$vo);
        }

        my $hlr = undef;
        if ( defined($vo_config{$vo}->{services}->{hlr}) ) {
          $hlr = $vo_config{$vo}->{services}->{hlr};
        }
        
        # VO-specific configuration
        # Hack required when both glite and wmproxy variants are enabled as
        # they use the same file with a different content. wmproxy variant
        # is a superset of glite variant, so produce only this one.
        
        if ( ($mw_variant ne 'glite') || !$mw_config{wmproxy}->{active} ) {
          # Build config file contents. Will return undefined value on an error. 
          my $rank = undef;
          my $requirements = undef;
          my $retryCount = undef;
          if ($config->elementExists($template_config."/defaultAttrs/CEAttrs/glue/rank")) {
              $rank = $config->getValue($template_config."/defaultAttrs/CEAttrs/glue/rank");
          } else {
              $rank = "-other.GlueCEStateEstimatedResponseTime";
          };
          if ($config->elementExists($template_config."/defaultAttrs/CEAttrs/glue/requirements")) {
              $requirements = $config->getValue($template_config."/defaultAttrs/CEAttrs/glue/requirements");
          } else {
              $requirements = "other.GlueCEStateStatus == \"Production\"";
          };
          if ($config->elementExists($template_config."/defaultAttrs/retryCount")) {
              $retryCount = $config->getValue($template_config."/defaultAttrs/retryCount");
          } else {
              $retryCount = "3";
          };
          
          my $contents;
          $contents = $self->buildVOConfig($vo_config{$vo}->{name},
                                           $default_contents,
                                           $myproxy,
                                           $hlr, 
                                           $ui_config{lbhosts},
                                           $ui_config{nshosts},
                                           $ui_config{wmproxies},
                                           $rank,
                                           $requirements,
                                           $retryCount,
                                          );
          unless ( defined($contents) ) {
            $self->error("Error generating $mw_variant UI configuration for VO $vo");
            next;
          }
          
          # Buid VO specific configuration file : there can be several files to generate to
          # accomodate regular changes in the name used by the tools to locate the file!
          # Ensure that the necessary directory exists.
          # Do a content comparaison with existing configuration ignoring comments.
          mkpath($mw_config{$mw_variant}->{configDir},0,0755);
          for my $vo_config_file (@{$mw_vo_config_file_defaults{$mw_variant}}) {
            $fname = $mw_config{$mw_variant}->{configDir} . "/" . $vo_config{$vo}->{name} . "/" .
                                                                          $vo_config_file;
            $result = $self->updateConfigFile($fname,$contents);
            if ( $result ) {
                $self->log("$fname updated");
            } else {
              $self->debug(1,"$mw_variant UI configuration for VO $vo up-to-date ($fname)");
            };          
          }
        } else {
          $self->debug(1,"glite UI configuration for VO $vo skipped (wmproxy variant also present)");
        }
  
      }
    }

    return 1;
}


# Update a configuration file after checking the contents have changed.
# Contents comparaison is done ignoring lines starting with a comment and empty lines.
# Contents is prepended with a comment indicating the config file is managed by this component.
# No message is printed, except in case of errors.
#
# Arguments :
#  - File name
#  - File contents
# Return value is LC::Check::file status.

sub updateConfigFile () {
  my $function_name = 'updateConfigFile';
  my ($self, $fname, $contents) = @_;
  unless ( defined($fname) ) {
    $self->error($function_name.":Missing required arguments : file name");
  }
  unless ( defined($contents) ) {
    $self->error($function_name.":Missing required arguments : contents");
  }
  
  # Use file_contents to retrieve current configuration to avoid problem with last \n
  my $old_contents='';
  if ( -f $fname ) {
    $old_contents = file_contents($fname);
  }
  if ( defined($old_contents) ) {
    my @old_contents = split /\n/, $old_contents;
    @old_contents = grep (/^[^#]/,@old_contents);
    $old_contents = join "\n", @old_contents;
    if ( length($old_contents) ) {
      $self->debug(2,"Current configuration file contents :\n$old_contents");
    } else {
      $self->debug(1,"Content of current configuration file is empty");
    }
  } else {
    $self->debug(1,"No existing version of configuration file found ($fname)")
  }
  
  my @new_contents = split /\n/, $contents;
  @new_contents = grep (/^[^#]/,@new_contents);
  my $new_contents = join "\n", @new_contents;
  if ( length($new_contents) ) {
    $self->debug(2,"New configuration file contents :\n$new_contents");
  } else {
    $self->debug(1,"Content of new configuration file is empty");
  }

  my $result = 0;
  if ( $new_contents ne $old_contents ) {
    my $contents = "#\n# Generated by ncm-wmsclient on " . localtime() . " - DO NOT EDIT\n#\n" . $contents;        
    $result = LC::Check::file($fname,
                              backup => ".old",
                              contents => $contents,
                             );
  };
  
  return $result;
};

# Generate the contents for a single VO entry.
# Defaults defined for all VOs are put again in VO specific files as
# in some UI variants (eg. gLite), system-wide defaults is provided as part of
# the distribution and is not intended to be modified.
# MyProxy server and HLR are always optional.
# Either LB/NS or WMProxy must be present but generally not both. This must be checked before.
# The same number of NS and LB proxies must be present.

sub buildVOConfig {

    my ($self,$voname, $default_contents, $myproxy, $hlr, $lbhosts, $nshosts, $wmproxies, $rank, $requirements, $retryCount) = @_;

    my $contents = "[\n";
    $contents .= "  VirtualOrganisation = \"$voname\";\n";
    $contents .= "  JdlDefaultAttributes = [\n";
    $contents .= "    rank = $rank;\n";
    $contents .= "    requirements = $requirements;\n";
    $contents .= "    RetryCount = $retryCount;\n";
    $contents .= "    MyProxyServer = \"$myproxy\";\n" if defined($myproxy);
    $contents .= "  ];";
    $contents .= "\n" . $default_contents . "\n";
    $contents .= "  MyProxyServer = \"$myproxy\";\n" if defined($myproxy);
    $contents .= "  HRLLocation = \"$hlr\";\n" if defined($hlr);

    # LB adressesses
    # Ensure LB/NS pairing by duplicating last LB entry as many times as necessary.
    if ( ref($lbhosts)) {
      my $ns_num = 0;
      if ( defined($nshosts) ) {
        $ns_num = @{$nshosts};
      }
      my $lb_num = @{$lbhosts};
      my $required_lb_num = $ns_num;
      $self->debug(2,"Number of NS=$ns_num, LB=$lb_num, required LB=$required_lb_num");
      $contents .= "  LBAddresses = {\n";
      my $first = 1;
      foreach my $v (@{$lbhosts}) {
        $contents .= ",\n" unless($first);
        $contents .= '                 "' . $v . '"';
        $first = 0;
      }
      for (my $i=$lb_num; $i<$required_lb_num; $i++ ) {
        $contents .= ",\n". '                 "' . $lbhosts->[$lb_num-1] . '"';
      }
      $contents .= "\n                };\n";
    }

    # Add the NS addresses if any
    if ( ref($nshosts)) {
      $contents .= "  NSAddresses = {\n";
      my $first = 1;
      foreach my $v (@{$nshosts}) {
        $contents .= ",\n" unless($first);
        $contents .= '                 "' . $v . '"';
        $first = 0;
      }
      $contents .= "\n                };\n";
    }
    
    # Add the WMProxy addresses if any
    if ( defined($wmproxies)) {
      $contents .= "  WMProxyEndpoints = {\n";
      my $first = 1;
      foreach my $v (@{$wmproxies}) {
        $contents .= ",\n" unless($first);
        $contents .= '                      "' . $v . '"';
        $first = 0;
      }
      $contents .= "\n                     };\n";
    }
        
    # Finish off the file.
    $contents .= "]\n";

    return $contents;
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
    $self->error($function_name.":Missing required arguments : NCM configuration");
  }
  unless ( defined($base) ) {
    $self->error($function_name.":Missing required arguments : configuration path");
  }
  unless ( defined($template) ) {
    $self->error($function_name.":Missing required arguments : template file");
  }

  my $translation = "";

  if (-e "$template") {
    open TMP, "<$template";
    while (<TMP>) {
      my $err = 0;
  
      # Special form for date.
      s/<%!date!%>/localtime()/eg;
  
      # Need quoted result (escape embedded quotes).
      s!<%"\s*(/[\w/]+)\s*(?:\|\s*(.+?))?\s*"%>!$self->quote($self->fill($config,$1,$2,\$err))!eg;
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

1;      # Required for PERL modules
