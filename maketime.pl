#!/usr/bin/env perl

use strict;
use warnings;
# This is the dhms maketime script,
# This script is run each time a new collection of code needs rolled into a .deb
# It expects to be in a 'packaging' directory in the root of the code, and for there to be certain
# files ready to template into place before building the package.

use Carp;
use FindBin;
use File::Slurp;
use File::Basename;
use YAML qw(LoadFile);
use lib "$FindBin::Bin/lib";
use Liip::YAML;

my $basedir = $FindBin::Bin;

#Check dhms has already been run to generate a config.pl,
#Config.pl should contain all the basic info needed to template files into place.
#Except for package-specific config items which are in the yaml manifest
unless ( -r 'config.pl' ) {
    croak qq{Cannot read packaging/config.pl\n - Make sure you are in a site checkout and have run dh-make-site};
}
require './config.pl';

my %config;
# Optionally pre-populate config options here, to be overridden by the config.pl (if set) eg:
#$config{greeting} = 'hello world';
%config = getconfig( %config );
my $config = \%config;
# Optionally override config options set in the package's config.pl here:
#$config{companysponsor} = 'Catalyst IT LTD';

my $appmanifest = LoadFile($basedir . '/../packagemanifest.yml');
$appmanifest = Liip::YAML::multi_mergekeys($appmanifest);
my $apps = $appmanifest->{apps};
my @appnames = keys %$apps;
foreach my $appname (@appnames) {
}

use constant TEMPLATE_DIR => 'packaging/debian_templates/';


my $renamefiles = '';
template_file(TEMPLATE_DIR . 'compat', 'debian/compat', $config);

foreach my $appname (@appnames) {

    $apps->{$appname}->{description} = $appname unless $apps->{$appname};

    my $wantsweb = wants_profile($apps->{$appname}, 'web');
    my $wantsdb = wants_profile($apps->{$appname}, 'db');
    my $isstatic = wants_profile($apps->{$appname}, 'static');

    if ($wantsdb) { #sanity check
        unless ($apps->{$appname}->{dbconfig}
            && $apps->{$appname}->{dbconfig}->{create}
            && $apps->{$appname}->{dbconfig}->{dbtypes}
        ) {
            die("$appname wants a database but didn't provide any config dbconfig key, required: create (bool) and dbtypes (string, comma separated)");
        }
        $config{DBTYPES} = $apps->{$appname}->{dbconfig}->{dbtypes};
        $config{DBCPREFIX} = $apps->{$appname}->{dbconfig}->{create} eq 'false' ? 'frontend.' : '';
    }
    my $destprefix = "debian/$config{PACKAGENAME}-$appname";

##### first issue any prebuild commands if we have them
    if ($apps->{$appname}->{prebuild}) {
        if (ref $apps->{$appname}->{prebuild} eq 'ARRAY') {
            foreach my $command (@{$apps->{$appname}->{prebuild}}) {
                system($command);
            }
        } else {
            system($apps->{$appname}->{prebuild});
        }
    }

##### dirs
    my $dirsdata = template_file_string(TEMPLATE_DIR . 'dirs', $config, $appname);
    $wantsweb && ($dirsdata .= template_file_string(TEMPLATE_DIR . 'dirs.web', $config, $appname));
    write_file("$destprefix.dirs", $dirsdata);

##### install
    my $installfile = create_installfile($config, $appname, $apps->{$appname});
    write_file($destprefix . '.install', $installfile);

##### cron
    if ($apps->{$appname}->{cron}) {
        my $scheduling;
        my $cron_data;
        foreach my $command (keys %{$apps->{$appname}->{cron}}) {
            $scheduling = $apps->{$appname}->{cron}->{$command};
            my $wwwroot = safe_wwwroot($config, $appname, 1);
            $cron_data.= "$scheduling www-data cd $wwwroot && php app/$appname/console $command\n";
        }
        write_file("$destprefix.cron.d", $cron_data);
    }

##### template
    template_file(TEMPLATE_DIR . 'templates', "$destprefix.templates", $config, $appname);

##### config
    my $configdata = template_file_string(TEMPLATE_DIR . 'config', $config, $appname);
    $wantsdb && ($configdata .= template_file_string(TEMPLATE_DIR . 'config.db', $config, $appname));
    $wantsweb && ($configdata .= template_file_string(TEMPLATE_DIR . 'config.web', $config, $appname));
    $isstatic || ($configdata .= template_file_string(TEMPLATE_DIR . 'config.dynamic', $config, $appname));

    write_file($destprefix . '.config', $configdata);

##### preinst
    my $preinst = template_file_string(TEMPLATE_DIR . 'preinst', $config, $appname);
    my $preinstweb = $wantsweb ?  template_file_string(TEMPLATE_DIR . 'preinst.web', $config, $appname) : '';
    $preinst =~ s/__PREINST.WEB__/$preinstweb/;
    write_file($destprefix . '.preinst', $preinst);

##### postinst
    my $postinst = template_file_string(TEMPLATE_DIR . 'postinst', $config, $appname);
    my $postinstconstantsweb = $wantsweb ?  template_file_string(TEMPLATE_DIR . 'postinst.constants.web', $config, $appname) : '';
    my $postinstconstantsdb = $wantsdb ?  template_file_string(TEMPLATE_DIR . 'postinst.constants.db', $config, $appname) : '';
    my $postinstconfigureweb = $wantsweb ?  template_file_string(TEMPLATE_DIR . 'postinst.configure.web', $config, $appname) : '';
    my $postinstconfigureendweb = $wantsweb ?  template_file_string(TEMPLATE_DIR . 'postinst.configure.end.web', $config, $appname) : '';
    my $postinstconfiguredb = $wantsdb ?  template_file_string(TEMPLATE_DIR . 'postinst.configure.db', $config, $appname) : '';
    my $postinstconfiguredynamic = !$isstatic ?  template_file_string(TEMPLATE_DIR . 'postinst.configure.dynamic', $config, $appname) : '';

    $postinst =~ s/__POSTINST.CONSTANTS.WEB__/$postinstconstantsweb/;
    $postinst =~ s/__POSTINST.CONSTANTS.DB__/$postinstconstantsdb/;
    $postinst =~ s/__POSTINST.CONFIGURE.WEB__/$postinstconfigureweb/;
    $postinst =~ s/__POSTINST.CONFIGURE.DB__/$postinstconfiguredb/;
    $postinst =~ s/__POSTINST.CONFIGURE.DYNAMIC__/$postinstconfiguredynamic/;
    $postinst =~ s/__POSTINST.CONFIGURE.END.WEB__/$postinstconfigureendweb/;

    write_file($destprefix . '.postinst', $postinst);

##### prerm
    my $prerm = template_file_string(TEMPLATE_DIR . 'prerm', $config, $appname);
    my $prermdb = $wantsdb ? template_file_string(TEMPLATE_DIR . 'prerm.db', $config, $appname) : '' ;
    my $prermweb = $wantsweb ?  template_file_string(TEMPLATE_DIR . 'prerm.web', $config, $appname) : '';
    $prerm =~ s/__PRERM.DB__/$prermdb/;
    $prerm =~ s/__PRERM.WEB__/$prermweb/;
    write_file($destprefix . '.prerm', $prerm);

##### postrm
    my $postrm = template_file_string(TEMPLATE_DIR . 'postrm', $config, $appname);
    my $postrmdb = $wantsdb ? template_file_string(TEMPLATE_DIR . 'postrm.db', $config, $appname) : '' ;
    $postrm =~ s/__POSTRM.DB__/$postrmdb/;
    write_file($destprefix . '.postrm', $postrm);


##### web only templates
    if ($wantsweb) {
        template_file(TEMPLATE_DIR . 'confmodule', "$destprefix.confmodule", $config, $appname);
        template_file(TEMPLATE_DIR . 'logrotate', "$destprefix.logrotate", $config, $appname);
        $config->{DOCROOTSUBDIR} = '';
        if ($apps->{$appname}->{docrootsubdir}) {
            $config->{DOCROOTSUBDIR} = $apps->{$appname}->{docrootsubdir};
        }
        foreach my $f qw(apache.conf.httpsonly apache.conf.http apache.conf.mixed apache.conf.redirect apachedir) {
            template_file(TEMPLATE_DIR . $f . '.template', "$destprefix.$f.template", $config, $appname);
        }
    }

##### special handling of frontend scripts
##### dh_install can't handle renames, so we have to rename this file to index.php specially
    if ($apps->{$appname}->{frontend}) {
        $renamefiles .= "\n\t" . 'mv $(CURDIR)/debian/_-_PACKAGENAME_-_-' . $appname . '/_-_WWWROOTNS_-_-' . $appname . '/web/' . $apps->{$appname}->{frontend}  . ' $(CURDIR)/debian/_-_PACKAGENAME_-_-' . $appname . '/_-_WWWROOTNS_-_-' . $appname . '/web/index.php';
    }
}

$config->{RENAMEFILES} = $renamefiles;
template_file(TEMPLATE_DIR . 'rules', 'debian/rules', $config);

chmod 0744,'debian/rules';

# control needs to be built up separately but in a different way
build_control_file(\@appnames, $apps);


# Build the package
`dpkg-buildpackage -rfakeroot -us -uc`;

`mv debian/changelog .`;
`rm debian/* -Rf`;
`mv changelog debian/`;

exit 0;

# Template specified input file into a specified file, searching for strings which
# 1 appear as keys in %config, and
# 2 are surrounded by the maketime templating marker "_-_",
# then replacing them with the corrosponding value in %config
# eg a file containing "Wanted to say _-_greeting_-_ from _-_packagename_-_"
# might be copied into coderoot/debian as: "Wanted to say hello world from moodle-site-hogwarts"
# If appname is specified, it is appended to the packagename, sitename, wwwroot and wwwrootns variables
sub template_file {
    my ($infile, $outfile, $subst, $appname) = @_;
    my $data = template_file_string($infile, $subst, $appname);
    write_file($outfile, $data);
}

# helper for template_file - returns the result as a string
# rather than writing it out to a file.
# for the arguments, see template_file comments.
sub template_file_string {
    my ($infile, $subst, $appname) = @_;
    my $data = read_file($infile);
    my $key;
    if ($appname) {
        $subst->{APPNAME} = $appname;
    }
    foreach $key ( keys %$subst ) {
        my $value = $subst->{$key};
        if ($appname && grep(/$key/, qw(PACKAGENAME SITENAME WWWROOT WWWROOTNS))) {
            $value .= '-' . $appname;
        }
        $value = '' unless defined $value;
        $data =~ s/_-_${key}_-_/$value/gxms;
    }
    return $data;
}

# Purely an abstraction function
# Called for each application to produce the debian install file - a list of files/directories that should be
# included in the deb, and where they should be copied on installation
sub create_installfile {
    my ($config, $appname, $app) = @_;
    my $installfile;

    # Default place to ask the deb to put things on install.
    my $safewwwroot = safe_wwwroot($config, $appname);
    my $destination = $config->{PACKAGENAME} . '-' . $appname;

    if (wants_profile($apps->{$appname}, 'web')) {
        $installfile .= sprintf("%-30s %s\n",
                "debian/$destination.apache.conf.redirect.template",
                "usr/share/packaged-site/$destination/");
        $installfile .= sprintf("%-30s %s\n",
                "debian/$destination.apache.conf.http.template",
                "usr/share/packaged-site/$destination/");
        $installfile .= sprintf("%-30s %s\n",
                "debian/$destination.apache.conf.httpsonly.template",
                "usr/share/packaged-site/$destination/");
        $installfile .= sprintf("%-30s %s\n",
                "debian/$destination.apache.conf.mixed.template",
                "usr/share/packaged-site/$destination/");
        $installfile .= sprintf("%-30s %s\n",
                "debian/$destination.apachedir.template",
                "usr/share/packaged-site/$destination/");
        $installfile .= sprintf("%-30s %s\n",
                "debian/$destination.confmodule",
                "usr/share/packaged-site/$destination/");
    }

    # each bundle needs to be copied
    if ($app->{bundles}) {
        foreach my $bundle (@{$app->{bundles}}) {
            my ($filename, $directories) = fileparse($bundle);
            $installfile .= sprintf("%-30s %s\n", $bundle, "$safewwwroot/$directories");
        }
    }

    # maybe it wants some other stuff too
    if ($app->{installfiles}) {
        foreach my $file (@{$app->{installfiles}}) {
            my ($filename, $directories) = fileparse($file);
            $installfile .= sprintf("%-30s %s\n", $file, "$safewwwroot/$directories");
        }
    }

    # front end script that is used to serve the application
    if ($app->{frontend}) {
        $installfile .= sprintf("%-30s %s\n", "web/$app->{frontend}", $safewwwroot . 'web/');
    }

    # published assets (hopefully created during pre-build)
    if ($app->{assets}) {
        foreach my $asset (@{$app->{assets}}) {
            $installfile .= sprintf("%-30s %s\n", $asset, $safewwwroot . 'web/');
        }
    }

    # if we are using a dynamic.yml file, copy the one from the debian templates
    # these should NOT get out of sync!
    my $isstatic = wants_profile($apps->{$appname}, 'static');
    unless ($isstatic) {
        $installfile .= sprintf("%-30s %s\n",
                    "packaging/debian_templates/dynamic.yml.template",
                    "usr/share/packaged-site/$destination/");
    }

    return $installfile
}

# build up the control file. start with the source package
# and then for each application, append a binary package section
sub build_control_file {
    # source package
    my ($appnames, $apps) = @_;

    # the template file already contains the source package declaration.
    # for each application we need to add a binary package declarataion from a template.
    my $control = template_file_string(TEMPLATE_DIR . 'control', $config);
    my @controlsubst = qw(DEPENDENCIES CONFLICTS RECOMMENDS SUGGESTS PREDEPENDS);

    foreach my $appname (@$appnames) {
        my $app = $apps->{$appname};
        foreach my $subst (@controlsubst) {
            $config->{$subst} = '';
            if ($app->{lc($subst)}) {
                foreach my $package (keys %{$app->{lc($subst)}}) {
                    $config->{$subst} .= $package;
                    if ($app->{lc($subst)}->{$package}) {
                        $config->{$subst} .= " ( $app->{lc($subst)}->{$package} )";
                    }
                    $config->{$subst} .= ' ,';
                }
                $config->{$subst} =~ s/.$//; # take off the last ,
            }
        }
        $config->{DESCRIPTION} = $apps->{$appname}->{description};
        if (wants_profile($app, 'db')) {
            $config->{PREDEPENDS} .= ', dbconfig-common';
        }
        $control .= template_file_string(TEMPLATE_DIR . 'control.binarytemplate', $config, $appname);
    }

    write_file('debian/control', $control);
}

# helper function to return the safe wwwroot for templating
sub safe_wwwroot {
    my ($config, $appname, $absolute) = @_;
    my $safewwwroot = $config->{WWWROOT} . '-' . $appname;
    $absolute || $safewwwroot =~ s/^\///;        # remove initial /
    $safewwwroot =~ s/(.*)([^\/])$/$1$2\//;  # add trailing /
    return $safewwwroot;

}

# helper to check to see if the given app wants a specific profile
sub wants_profile {
    my $app = shift;
    my $profile = shift;
    return grep(/^$profile$/, @{$app->{profiles}});
}
