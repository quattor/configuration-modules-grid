# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/gold/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component_server = {
    "super.user"                                           : string    = 'root'
    "server.host"                                          : string    = 'localhost.localdomain'
    "server.port"                                          ? long      # 7112
    "database.datasource"                                  : string    = 'DBI:Pg:dbname=gold;host=localhost.localdomain'
    "database.user"                                        ? string    # NONE
    "database.password"                                    ? string    # NONE
    "response.chunksize"                                   : long      = 100000
    "currency.precision"                                   ? long      # 0
    "security.authentication"                              ? string    # true
    "security.encryption"                                  ? string    # false
    "account.autogen"                                      ? string    # true
    "allocation.autogen"                                   ? string    # true
    "machine.autogen"                                      ? string    # false
    "machine.default"                                      ? string    # NONE
    "project.autogen"                                      ? string    # false
    "project.default"                                      ? string    # NONE
    "user.autogen"                                         ? string    # false
    "user.default"                                         ? string    # NONE
    "log4perl.logger"                                      : string    = 'TRACE, Log, Screen'
    "log4perl.appender.Log.Threshold"                      : string    = 'TRACE'
    "log4perl.appender.Screen.Threshold"                   : string    = 'FATAL'
    "log4perl.logger.Message"                              ? string    # TRACE,
    "log4perl.appender.Log"                                ? string    # Log::Log4perl::Appender::File
    "log4perl.appender.Log"                                : string    = 'Log::Dispatch::FileRotate'
    "log4perl.appender.Log.filename"                       : string    = '/usr/local/gold/log/goldd.log'
    "log4perl.appender.Log.mode"                           : string    = 'append'
    "log4perl.appender.Log.size"                           : long      = 10000000
    "log4perl.appender.Log.max"                            : long      = 7
    "log4perl.appender.Log.layout"                         : string    = 'PatternLayout'
    "log4perl.appender.Log.layout.ConversionPattern"       : string    = '%d{yyyy-MM-dd HH:mm:ss.SSS} %-5p %M  %m%n'
    "log4perl.appender.Screen"                             : string    = 'Log::Log4perl::Appender::Screen'
    "log4perl.appender.Screen.layout"                      : string    = 'PatternLayout'
    "log4perl.appender.Screen.layout.ConversionPattern"    : string    = '%d{yyyy-MM-dd HH:mm:ss.SSS} %-5p %M [%F:%L]  %m%n'
};


type ${project.artifactId}_component_client = {
    "server.host"                                          : string    = 'localhost.localdomain'
    "server.port"                                          ? long      # 7112
    "server.backup"                                        ? string    # NONE
    "security.authentication"                              ? string    # true
    "security.encryption"                                  ? string    # false
    "security.token.type"                                  ? string    # symmetric
    "wire.protocol"                                        ? string    # SSSRMAP
    "response.chunking"                                    ? string    # false
    "response.chunksize"                                   ? long      # 0
    "currency.precision"                                   ? long      # 0
    "account.show"                                         ? string    # Id,Name,Amount,Projects,Users,Machines,Description
    "allocation.show"                                      ? string    # Id,Account,Active,StartTime,EndTime,Amount,CreditLimit,Deposited
    "balance.show"                                         ? string    # Id,Name,Amount,Reserved,Balance,CreditLimit,Available
    "job.show"                                             ? string    # Id,JobId,User,Project,Machine,Queue,QualityOfService,Stage,Charge,Processors,Nodes,WallDuration,StartTime,EndTime,Description
    "machine.show"                                         ? string    # Name,Active,Architecture,OperatingSystem,Description
    "project.show"                                         ? string    # Name,Active,Users,Machines,Description
    "quotations.show"                                      ? string    # Id,Amount,Job,Project,User,Machine,StartTime,EndTime,WallDuration,Uses,ChargeRates,Description
    "reservation.show"                                     ? string    # Id,Name,Amount,StartTime,EndTime,Job,User,Project,Machine,Accounts,Description
    "transaction.show"                                     ? string    # Id,Object,Action,Actor,Name,Child,JobId,Amount,Delta,Account,Project,User,Machine,Allocation,Count,Description
    "user.show"                                            ? string    # Name,Active,CommonName,PhoneNumber,EmailAddress,DefaultProject,Description
    "log4perl.logger"                                      : string    = 'TRACE, Log, Screen'
    "log4perl.appender.Log.Threshold"                      : string    = 'INFO'
    "log4perl.appender.Screen.Threshold"                   : string    = 'FATAL'
    "log4perl.logger.Message"                              ? string    # TRACE,
    "log4perl.appender.Log"                                ? string    # Log::Log4perl::Appender::File
    "log4perl.appender.Log"                                : string    = 'Log::Dispatch::FileRotate'
    "log4perl.appender.Log.filename"                       : string    = '/usr/local/gold/log/gold.log'
    "log4perl.appender.Log.filename"                       ? string    # sub
    "log4perl.appender.Log.mode"                           : string    = 'append'
    "log4perl.appender.Log.size"                           : long      = 10000000
    "log4perl.appender.Log.max"                            : long      = 7
    "log4perl.appender.Log.layout"                         : string    = 'PatternLayout'
    "log4perl.appender.Log.layout.ConversionPattern"       : string    = '%d{yyyy-MM-dd HH:mm:ss.SSS} %-5p %M  %m%n'
    "log4perl.appender.Screen"                             : string    = 'Log::Log4perl::Appender::Screen'
    "log4perl.appender.Screen.layout"                      : string    = 'PatternLayout'
    "log4perl.appender.Screen.layout.ConversionPattern"    : string    = '%d{yyyy-MM-dd HH:mm:ss.SSS} %-5p %M [%F:%L]  %m%n'
};

type ${project.artifactId}_component_cgiclient = {
    "server.host"                                          : string    = 'localhost.localdomain'
    "server.port"                                          ? long      # 7112
    "server.backup"                                        ? string    # NONE
    "security.authentication"                              ? string    # true
    "security.encryption"                                  ? string    # false
    "security.token.type"                                  ? string    # symmetric
    "response.chunking"                                    ? string    # false
    "response.chunksize"                                   ? long      # 0
    "currency.precision"                                   ? long      # 0
    "log4perl.logger"                                      : string    = 'TRACE, Log, Screen '
    "log4perl.appender.Log.Threshold"                      : string    = 'INFO'
    "log4perl.appender.Screen.Threshold"                   : string    = 'FATAL'
    "log4perl.logger.Message"                              ? string    # TRACE,
    "log4perl.appender.Log"                                ? string    # Log::Log4perl::Appender::File
    "log4perl.appender.Log"                                : string    = 'Log::Dispatch::FileRotate'
    "log4perl.appender.Log.filename"                       : string    = '/usr/local/gold/log/goldg.log'
    "log4perl.appender.Log.filename"                       ? string    # sub
    "log4perl.appender.Log.mode"                           : string    = 'append'
    "log4perl.appender.Log.size"                           : long      = 10000000
    "log4perl.appender.Log.max"                            : long      = 7
    "log4perl.appender.Log.layout"                         : string    = 'PatternLayout'
    "log4perl.appender.Log.layout.ConversionPattern"       : string    = '%d{yyyy-MM-dd  HH:mm:ss} %-5p %M  %m%n'
    "log4perl.appender.Screen"                             : string    = 'Log::Log4perl::Appender::Screen'
    "log4perl.appender.Screen.layout"                      : string    = 'PatternLayout'
    "log4perl.appender.Screen.layout.ConversionPattern"    : string    = '%d{yyyy-MM-dd HH:mm:ss.SSS} %-5p %M [%F:%L]  %m%n'
};

type ${project.artifactId}_component = {
    include structure_component

    'configPath' : string = "/usr/local/gold/etc"
    
    ## the secret key
    "auth_key"      : string

    ## always configure client    
    "client"    : ${project.artifactId}_component_client 

    "cgiclient"    ? ${project.artifactId}_component_cgiclient 
    
    ## optional server configuration
    "server"    ? ${project.artifactId}_component_server 
};

bind '/software/components/gold' = ${project.artifactId}_component;


