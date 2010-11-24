
use strict;
use warnings;
# This is the dhms maketime script,
# This script is run each time a new collection of code needs rolled into a .deb
# It expects to be in a 'packaging' directory in the root of the code, and for there to be certain
# files ready to template into place before building the package.

use Carp;
use FindBin;
use File::Slurp;
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
# Optionally override config options set in the package's config.pl here:
#$config{companysponsor} = 'Catalyst IT LTD';

my $appmanifest = LoadFile($basedir . '/../packagemanifest.yml');
$appmanifest = Liip::YAML::multi_mergekeys($appmanifest);
my $apps = $appmanifest->{apps};
my @appnames = keys %$apps;
foreach my $appname (@appnames) {
    if ($apps->{$appname}->{prebuild}) {
        if (ref $apps->{$appname}->{prebuild} eq 'ARRAY') {
            foreach my $command (@{$apps->{$appname}->{prebuild}}) {
                exec($command);
            }
        } else {
            exec($apps->{$appname}->{prebuild});
        }
    }
}

use constant TEMPLATE_DIR => 'packaging/debian_templates/';
# Get a list of files that need templating:
my %templatefiles = list_template_files();

# Step through the listed files, templating them into TEMPLATE_DIR using variables from %config and the app if relevant
foreach my $templatefile (keys %templatefiles) {
    my $destination;
    if ($templatefiles{$templatefile} == 1) {
        foreach my $appname (@appnames) {
            $destination = 'debian/' . $config{PACKAGENAME}  . '.' . $templatefile;
            template_file(TEMPLATE_DIR . $templatefile, $destination, %config, $appname);
        }
    } else {
        $destination = 'debian/' . $templatefile;
        template_file(TEMPLATE_DIR . $templatefile, $destination, %config);
    }

}
chmod 0744,'debian/rules';

foreach my $appname (@appnames) {
    my $installfile = create_installfile(%config, $appname, $apps->{$appname});
    write_file('debian/' . $appname . '.install', $installfile);
    if ($apps->{$appname}->{cron}) {
        # check if it's an array or a scalar
        # TODO lukas
        my $stuff = '';
        write_file('debian/' . $appname . '.cron', $stuff);
    }
}

# control needs to be built up separately but in a different way
build_control_file(\@appnames, $apps);

# Create the file that tells the deb what files to put where

# Build the package
`dpkg-buildpackage -rfakeroot -us -uc`;

`mv debian/changelog .`; # TODO all changelogs files
`rm debian/* -Rf`;
`mv changelog debian/`; # TODO all changelogs files

exit 0;

# Template specified input file into a specified file, searching for strings which
# 1 appear as keys in %config, and 
# 2 are surrounded by the maketime templating marker "_-_",
# then replacing them with the corrosponding value in %config
# eg a file containing "Wanted to say _-_greeting_-_ from _-_packagename_-_"
# might be copied into coderoot/debian as: "Wanted to say hello world from moodle-site-hogwarts"
sub template_file {
    my ($infile, $outfile, %subst, $appname) = @_;

    my $data = read_file($infile);
    my $key;
    foreach $key ( keys %subst ) {
        my $value = $subst{$key};
        if ($appname) {
            $value .= '-' . $appname;
        }
        $value = '' unless defined $value;
        $data =~ s/_-_${key}_-_/$value/gxms;
    }
    write_file($outfile, $data);
}

# Purely an abstraction function
# Called once to produce the debian install file - a list of files/directories that should be
# included in the deb, and where they should be copied on installation
sub create_installfile {
    my (%config, $appname, $app) = @_;
    my $installfile;

    # Default place to ask the deb to put things on install.
    my $safewwwroot = $config{WWWROOT} . '-' . $appname;
    $safewwwroot =~ s/^\///;        # remove initial /
    $safewwwroot =~ s/(.*)([^\/])$/$1$2\//;  # add trailing /

    if (grep('/^web$/', $app->{profiles})) {
        $installfile .= sprintf("%-30s %s\n",
                'debian/apache.conf.redirect.template',
                'usr/share/packaged-site/' . $config{PACKAGENAME} . '/');
        $installfile .= sprintf("%-30s %s\n",
                'debian/apache.conf.http.template',
                'usr/share/packaged-site/' . $config{PACKAGENAME} . '/');
        $installfile .= sprintf("%-30s %s\n",
                'debian/apache.conf.httpsonly.template',
                'usr/share/packaged-site/' . $config{PACKAGENAME} . '/');
        $installfile .= sprintf("%-30s %s\n",
                'debian/apache.conf.mixed.template',
                'usr/share/packaged-site/' . $config{PACKAGENAME} . '/');
        $installfile .= sprintf("%-30s %s\n",
                'debian/apachedir.template',
                'usr/share/packaged-site/' . $config{PACKAGENAME} . '/');
    }
    $installfile .= sprintf("%-30s %s\n",
            'debian/confmodule',
            'usr/share/packaged-site/' . $config{PACKAGENAME} . '/');


    if ($app->{bundles}) {
        foreach my $bundle (@{$app->{bundles}}) {
            $installfile .= sprintf("%-30s %s\n", $bundle, $safewwwroot);
        }
    }

    # maybe it wants some other stuff too
    if ($app->{installfiles}) {
        foreach my $installfile (@{$app->{installfiles}}) {
            $installfile .= sprintf("%-30s %s\n", $installfile, $safewwwroot);
        }
    }

    if ($app->{frontend}) {
        $installfile .= sprintf("%-30s %s\n", $app->{frontend}, "$safewwwroot/index.php");
    }

    if ($app->{assets}) {
        #TODO assets
    }

    return $installfile
}

# Purely an abstraction function:
# Create an array of files that require templating into <coderoot>/debian
sub list_template_files {
    return (
        #'control'                        => 0,
        'compat'                         => 0,
        'rules'                          => 0,
        'dirs'                           => 1,
        'config'                         => 1,
        'templates'                      => 0,
        'apache.conf.redirect.template'  => 0,
        'apache.conf.http.template'      => 0,
        'apache.conf.httpsonly.template' => 0,
        'apache.conf.mixed.template'     => 0,
        'apachedir.template'             => 0,
        'preinst'                        => 1,
        'postinst'                       => 1,
        'postrm'                         => 1,
        'prerm'                          => 1,
        'confmodule'                     => 0,
        'logrotate'                      => 1,
    );
}

sub build_control_file {
    # source package
    my ($appnames, $apps) = @_;

    # the template file already contains the source package declaration.
    # for each application we need to add a binary package declarataion from a template.
    #TODO



}
