#!/usr/bin/env perl

use strict;
use warnings;
# This is the dhms maketime script,
# This script is run each time a new collection of code needs rolled into a .deb
# It expects to be in a 'packaging' directory in the root of the code, and for there to be certain
# files ready to template into place before building the package.

use Carp;
use FindBin;
use File::Basename;
use File::Slurp;
use YAML qw(LoadFile);
use lib "$FindBin::Bin/lib";
use Liip::YAML;
use Liip::Symfony2::Application;
use Liip::Debian::Helper;

my $basedir = "$FindBin::Bin/..";

#Check dhms has already been run to generate a config.pl,
#Config.pl should contain all the basic info needed to template files into place.
#Except for package-specific config items which are in the yaml manifest
unless ( -r 'config.pl' ) {
    croak qq{Cannot read packaging/config.pl\n - Make sure you are in a site checkout and have run dh-make-site};
}
require './config.pl';

my %globalconfig;
# Optionally pre-populate config options here, to be overridden by the config.pl (if set) eg:
#$globalconfig{greeting} = 'hello world';
# TODO replace with yml data
%globalconfig = getconfig( %globalconfig );
# Optionally override config options set in the package's config.pl here:
#$globalconfig{companysponsor} = 'Catalyst IT LTD';

my $appmanifest = LoadFile($basedir . '/packagemanifest.yml');
$appmanifest = Liip::YAML::multi_mergekeys($appmanifest);
my $appprofiles = $appmanifest->{apps};
my $apps;

my $renamefiles = '';
my $helper = Liip::Debian::Helper->new(\%globalconfig);

$helper->template_file('compat', 'debian/compat', {foo => 'bar'});

foreach my $appname (keys %$appprofiles) {

    my $destprefix = "$globalconfig{PACKAGENAME}-$appname";
    my $app = Liip::Symfony2::Application->new($appname, $appprofiles->{$appname}, $basedir, $helper, $destprefix);

    $app->sanity_check();

    $app->prebuild();

    $app->make_dynamic_yml();

    $app->make_dynamic_debian_constructs();

    $app->make_dirs();

    $app->make_install();

    $app->make_cron();

    $app->make_templates();

    $app->make_config();

    $app->make_preinst();

    $app->make_postinst();

    $app->make_prerm();

    $app->make_postrm();

    $app->make_apache_config();

    $apps->{$appname} = $app;

    $renamefiles .= $app->get_renames();
}

$globalconfig{RENAMEFILES} = $renamefiles;
$helper->template_file('rules', 'debian/rules', \%globalconfig);

chmod 0744,'debian/rules';

# control needs to be built up separately but in a different way
$helper->build_control_file($apps);

# Build the package
`dpkg-buildpackage -rfakeroot -us -uc --source-option=--format='3.0 (native)'`; # use native to stop complaints about <packagename>.<upstreamversion>
if ($? gt 0) {
    die("It appears dpkb-buildpackage failed to run. Not cleaning out the debian directory!");
    exit 1;
}

`mv debian/changelog .`;
`rm debian/* -Rf`;
`mv changelog debian/`;

exit 0;


