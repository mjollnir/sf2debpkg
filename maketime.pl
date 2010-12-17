#!/usr/bin/env perl

use strict;
use warnings;
# This is the dhms maketime script,
# This script is run each time a new collection of code needs rolled into a .deb
# It expects to be in a 'packaging' directory in the root of the code, and for there to be certain
# files ready to template into place before building the package.

use Carp;
use FindBin;
use Cwd;
use File::Basename;
use File::Slurp;
use File::Copy;
use YAML qw(LoadFile);
use lib "$FindBin::Bin/lib";
use Liip::YAML;
use Liip::Symfony2::Application;
use Liip::Debian::Helper;

my $basedir = "$FindBin::Bin";
my $cwd = getcwd();

if ($basedir eq $cwd) {
    croak qq(Make sure this script is run from the base of your Symfony2 checkout);
}

my $ptemplatedir = "$cwd/packaging/project_templates/";

my $config = {};
# if the packagemanifest exists, load it first so that we can create the changelog with helpful defaults
if ( -r "$cwd/packagemanifest.yml") {
    $config = LoadFile("$cwd/packagemanifest.yml");
    $config = Liip::YAML::multi_mergekeys($config);
}

# basic dependencies to build the package are:
# packagemanifest.yml
# debian/changelog
# Makefile
my $dependenciesmissing = [];

my $dependencies = {
    Makefile => 'Makefile',
    'packagemanifest.yml' => 'packagemanifest.yml',
    'changelog' => 'debian/changelog',
};

foreach my $dep (keys %$dependencies) {
    my $destination = $dependencies->{$dep};
    next if (-r $destination);
    copy("$ptemplatedir/$dep", "$cwd/$destination");
    push @$dependenciesmissing, $dep;
}

# if any of these are not present, we can create skeletons and exit
if (scalar @$dependenciesmissing gt 0) {
    my $sensiblechangelog = 0;
    if (scalar keys %$config && grep(/changelog/, @$dependenciesmissing)) {
        $config->{project}->{projectname} && `sed -i "s/YOURPROJECT/$config->{project}->{projectname}/" debian/changelog`;
        $config->{project}->{maintainername} && `sed -i "s/YOURNAME/$config->{project}->{maintainername}/" debian/changelog`;
        $config->{project}->{maintaineremail} && `sed -i "s/YOU\@EXAMPLE.COM/$config->{project}->{maintaineremail}/" debian/changelog`;
        $sensiblechangelog = 1;
    }
    print "Some dependencies were missing. I created examples for you:\n    ";
    print join ("\n    ",  @{$dependencies}{@$dependenciesmissing});
    print "\nPlease check them, commit them to your project, and try building again.\n";
    if (grep(/Makefile/, @$dependenciesmissing)) {
        print "Additionally, I created a Makefile for you, so you can now just run 'make' in your project root'\n";
    }
    if (!$sensiblechangelog && grep(/changelog/, @$dependenciesmissing)) {
        print "Your debian/changelog in particular needs checking!\n";
    }
    exit;
}

# ok, if we've got this far, all the dependencies are present and we're good to go
my $appprofiles = $config->{apps};
my $globalconfig = $config->{project};

unless ($appprofiles && $globalconfig) {
    die "Misformed yml structure? apps: and project: must both be present!";
}

unless ($globalconfig->{projectname} && $globalconfig->{maintainername} && $globalconfig->{maintaineremail}) {
    die "Misformed yaml structure? proejct: must contain projectname: and maintainername: and maintaineremail";
}

# backwards compatibility - all these used to be in the old config.pl, and are used as substvars:
my $bcconfig = {
    PACKAGENAME => 'symfony2-site-' . $globalconfig->{projectname},
    SITETYPE    => 'symfony2',
    SITENAME    => $globalconfig->{projectname},
    WWWROOT     => '/var/www/symfony2-site-' . $globalconfig->{projectname},
    WWWROOTNS   => 'var/www/symfony2-site-' . $globalconfig->{projectname},
    FULLNAME    => $globalconfig->{maintainername},
    EMAIL       => $globalconfig->{maintaineremail},
};

@{$globalconfig}{keys %$bcconfig} = values %$bcconfig;

my $apps;

my $renamefiles = ''; # dh_install can't rename files, so this is done manually in debian/rules
my $helper = Liip::Debian::Helper->new($globalconfig);

$helper->template_file('compat', 'debian/compat', {foo => 'bar'});

foreach my $appname (keys %$appprofiles) {

    my $destprefix = "$globalconfig->{PACKAGENAME}-$appname";
    my $app = Liip::Symfony2::Application->new($appname, $appprofiles->{$appname}, $cwd, $helper, $destprefix);

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

    $renamefiles .= $app->get_renames();

    $apps->{$appname} = $app; # store this for building up debian/control
}

$globalconfig->{RENAMEFILES} = $renamefiles;
$helper->template_file('rules', 'debian/rules', $globalconfig);

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


