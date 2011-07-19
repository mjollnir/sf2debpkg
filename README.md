Introduction
============

The goal of the packaging solution is to generate native debian packages for Symfony2 applications. This allows leveraging the debian dependency system and package repository solutions. Questions asked during the installation take away the guess work what server specific settings need to be set. Furthermore having all packages installed via the debian system enables the creation of tools that determine what version is installed on what server, which is useful for example to determine the impact of backward compatibility breaks or what server needs to be updated when security fixes are made available.

The packaging system using a similar approach to the Moodle/Mahara/Drupal packaging used at Liip based on the work done at Catalyst. Nothing is committed to the Symfony2 project except metadata, and the package is built from templates inside the packaging "submodule" (normally a git submodule, in this case a vendor). Multiple binary packages are built from a single source package, defined by packagemanifest.yml in the root of the symfony2 directory.

Overview
========

The logic for templating all the files from the packaging "submodule" into the debian/ directory before calling dpkg-buildpackage, is all handed in packaging/maketime.pl. This file parses the packagemanifest.yml, and for each application in there, starts building up the binary package definitions and templates everything into debian/.

The best way to understand it is to read it, but the most important thing to understand, is that this is the script that combines the declarations in packagemanifest.yml, the templates in packaging/debian_templates and writes the output into debian/.

It also calls dpkg-buildpackage to actually build the debian packages, and then clears out the debian/ directory again afterwards.

Setup
=====

To setup the packaging scripts you can use git to either clone the sitepackaging repository in to your Symfony2 projects root directory or set it up as a submobule at your own discretion:

    git clone git://github.com/mjollnir/sf2debpkg.git packaging

Make sure the following debian packages are installed

    sudo apt-get install dpkg-dev
    sudo apt-get install debhelper
    sudo apt-get install devscripts
    sudo apt-get install libconfig-yaml-perl
    sudo apt-get install libfile-slurp-perl

Initial Run
===========

To generate skeleton packagemanifest.yml, Makefile and debian/changelog files run the following command:
    ./packaging/maketime.pl

Assumptions
===========

Application structure
---------------------

The packager assumes that a custom directory structure is used for the application kernels. Specifically each application kernel is stored inside a subdirectory of an "app" directory. With this structure its possible for the installer to generate multiple separate packages for each kernel. This requires some minimal changes to the frontcontroller and kernel files. Note this also requires some changes to the createKernel() method in the WebTestCase class, which are implemented in FunctionalTestBundle.

web/main.php (will be installed as web/index.php)

    <?php

    require_once __DIR__.'/../app/bootstrap.php';
    require_once __DIR__.'/../app/main/MainKernel.php';

    use Symfony\Component\HttpFoundation\Request;

    $kernel = new MainKernel('prod', false);
    //$kernel = new MainCache(new MainKernel('prod', false));
    $kernel->handle(Request::createFromGlobals())->send();

app/main/MainKernel.php

    <?php

    use Symfony\Component\HttpKernel\Kernel;
    use Symfony\Component\DependencyInjection\Loader\LoaderInterface;

    class MainKernel extends Kernel
    {
        public function registerRootDir()
        {
            return __DIR__;
        }

        public function registerBundles()
        {
            $bundles = array(
                new Symfony\Bundle\FrameworkBundle\FrameworkBundle(),

                // enable third-party bundles
            );

            if ($this->isDebug()) {
                $bundles[] = new Symfony\Bundle\WebProfilerBundle\WebProfilerBundle();
            }

            return $bundles;
        }

        public function registerContainerConfiguration(LoaderInterface $loader)
        {
            // use YAML for configuration
            // comment to use another configuration format
            $loader->load(__DIR__.'/config/config_'.$this->getEnvironment().'.yml');
        }
    }


packagemanifest.yml
-------------------

This file defines the multiple applications that are built by the packaging procedure. In case it needs stating, you can quote single quotes like so ' something ''quoted'' '. The rough structure is so:

packagemanifest.yml

    constants:
        database: &database
            'php5-pgsql': ~
            'postgresql-client': ~
        web: &web
            'php5': '>=5.3.0'
            'libapache2-mod-php5': ~
            'php5-curl': ~

    project:
        projectname: yourproject
        maintainername: 'Your Team Name'
        maintaineremail: 'you@email.com'

    apps:
        main:
            frontend: main.php
            description: 'Main website'
            dependencies:
               << : [ *database, *web ]
            conflicts: ~
            recommends: ~
            suggests: ~
            predepends: ~
            cron:
                #'some:console:command': "0-5/2 * * * *"
            bundles:
                - 'vendor/symfony'
                - 'vendor/zend/library/Zend/Log'
                - 'vendor/swiftmailer'
                - 'vendor/doctrine'
                - 'vendor/doctrine-migrations'
                - 'vendor/doctrine-dbal'
                - 'vendor/doctrine-common'
                - 'vendor/twig'
                - 'src/Acme/YourBundle'
            assets: ~
            profiles:
                - 'web'
                - 'db'
            dbconfig:
                dbtypes: pgsql
                create: false
            postinst: ~
            debianpostinst: 'shell commands to run "as is" (you can use _-_WWWROOT_-_ and it will be replaced)
            installfiles:
                - 'app/main'
                - 'src/autoload.php'
                - 'app/boostrap.php.cache'

        dbmigration:
            description: 'DB Schema and Migrations package'
            dependencies:
                'php5-cli': ~
            bundles:
              - 'vendor/doctrine'
              - 'vendor/symfony'
              - 'vendor/doctrine-migrations'
              - 'vendor/doctrine-data-fixtures'
              - 'vendor/doctrine-dbal'
              - 'vendor/doctrine-common'
              - 'src/Acme/YourBundle'
            assets: ~
            profiles:
                - 'db'
            dbconfig:
                dbtypes: pgsql
                create: false
            postinst:
                - 'doctrine:migrations:migrate -n -q'
                #- 'doctrine:data:load --fixtures=src/Acme/YourBundle/Resources/data/fixtures --append=true'
            installfiles:
                - 'app/dbmigration'
                - 'app/autoload.php'
                - 'app/bootstrap.php.bin'

        static:
            description: 'All static website content'
            prebuild:
                - 'cp app/main/config/dynamic.yml.dist app/main/config/dynamic.yml'
                - 'app/main/console assets:install web'
                - 'app/main/console asetic:dump web'
                - 'rm app/main/config/dynamic.yml'
            dependencies:
                <<: *web
            bundles: ~
            assets:
                - 'web/bundles/'
                - 'web/css/'
                - 'web/js/'
            profiles:
                - 'web'
                - 'static'
            installfiles:
                - 'app/static'

dynamic.yml
-----------

The dynamic.yml should be included and used (rather than config.yml) for all dynamic config options that are dependant on which machine symfony2 is installed upon. For example, database connection details or urls. During the installation a dynamic.yml.dist is parsed if it exists. For each line the in the config the installer will ask for a value to generate the dynamic.yml. The dynamic.doctrine.dbal.default values are built from a template if the 'db' profile is required, and other parameters can be added into it with debconf during package installation using key/value pairs.

    app/main/config/dynamic.yml.dist

    parameters:
        dynamic.bar: 123
        dynamic.doctrine.dbal.default:
            driver:   pdo_pgsql
            dbname:   XXXXXXXX
            user:     XXXXXXXX
            password: ~

The dynamic.yml can then be imported into config.yml.

app/main/config/config.yml

    imports:
        - { resource: dynamic.yml }

    doctrine.dbal:
        connections:
            default:
                %dynamic.doctrine.dbal.default%

    foo.config:
        bar: %dynamic.bar%

Note: Right now there is a "hack" for handling writing the proper PDO driver when using the "dbconfig" settings. As a result the dynamic.yml is manipulated after Debian has created the file. As a result Debian will think that the user has done local changes to the config file during the installation. As a result when asked say yes to the question of to "OVERWRITE WITH THE PACKAGE MAINTAINER'S VERSION".

Apache settings
---------------

By default a mod_rewrite setting will be installed to point every non existent file in the web root to index.php (note that webappname.php will be installed as index.php). However additional configurations can be done with an apachesettings file.
Hint: the installation paths are defined at "make" time and are derived from the package name. So it is safe to put a hardcoded path value into the apachesettings file since the installation paths are known (example: /var/www/<package name>/web for the document root).


app/main/config/apachesettings

    # directives can be placed here, to be included into the virtualhost

    __APACHE_DEFAULT_REWRITE__

The debian/ files
-----------------

The following table lists the files are used in the packaging (in the build directory, "debian/" during make time):

| filename                                      | purpose                                                                                                               |
|:----------------------------------------------|:----------------------------------------------------------------------------------------------------------------------|
| changelog                                     | global changelog - used to define the debian version                                                                  |
| compat                                        | debian compatibilitiy version                                                                                         |
| control                                       | source and binary packages declaration including dependencies                                                         |
| rules                                         | makefile for building the package - uses dh_ (debhelper) mostly                                                       |
| PACKAGENAME.apache.conf.httpsonly.template    | apache config for pure https sites                                                                                    |
| PACKAGENAME.apache.conf.http.template         | apache config for pure https sites                                                                                    |
| PACKAGENAME.apache.conf.mixed.template        | apache config for mixed http/https sites                                                                              |
| PACKAGENAME.apache.conf.redirect.template     | apache config for redirects (eg wwww.SITE -> SITE)                                                                    |
| PACKAGENAME.apachedir.template                | apache config for the document root                                                                                   |
| PACKAGENAME.config                            | debconf questions to ask during package installation                                                                  |
| PACKAGENAME.confmodule                        | helper for sites that use apache - does graceful restarting and ssl checking                                          |
| PACKAGENAME.cron.d                            | file to be dropped into /etc/cron.d - contains multiple lines - one for each cronjob defined in packagemanifest.yml   |
| PACKAGENAME.dynamic.yml.template              | used for the questions during install to generate the dynamic.yml                                                     |
| PACKAGENAME.dirs                              | list of directories on the filesystem thought to be "owned" by the package (will be created)                          |
| PACKAGENAME.install                           | list of files to install on the filesystem that the package considers to "own"                                        |
| PACKAGENAME.logrotate                         | file to be dropped into /etc/logrotate.d - web profiles will contain a snippet to rotate the apache logs              |
| PACKAGENAME.postinst                          | main logic during installation happens here, like templating the config files and trying to connect to the database   |
| PACKAGENAME.postrm                            | script to handle logic after the package is removed                                                                   |
| PACKAGENAME.preinst                           | script to handle logic before the package is installed (for example to early exit)                                    |
| PACKAGENAME.prerm                             | script to handle logic before the package is removed                                                                  |
| PACKAGENAME.templates                         | language files and datatype declarations for debconf (see PACKAGENAME.config file)                                    |

The debian_templates files
--------------------------

The following table lists the template files in the packaging "submodule" packaging/debian_templates. These are templated into debian/ during make time.

| filename                          | purpose                                                                                       |
|:----------------------------------|:----------------------------------------------------------------------------------------------|
| apache.conf.httpsonly.template    | see above section in debian/ directory                                                        |
| apache.conf.http.template         | see above section in debian/ directory                                                        |
| apache.conf.mixed.template        | see above section in debian/ directory                                                        |
| apache.conf.redirect.template     | see above section in debian/ directory                                                        |
| apachedir.template                | see above section in debian/ directory                                                        |
| compat                            | see above section in debian/ directory                                                        |
| config                            | see above section in debian/ directory                                                        |
| config.db                         | questions for apps using the "db" profile, included in main 'config'                          |
| config.web                        | questions for apps using the "web" profile, included in main 'config'                         |
| confmodule                        | see above section in debian/ directory                                                        |
| control                           | source package declaration                                                                    |
| control.binarytemplate            | template file for each binary package defined in the package manifest, appended to control    |
| dirs                              | see above section in debian/ directory                                                        |
| dirs.web                          | additional dirs for apps using the "web" profile                                              |
| install                           | see above section in debian/ directory                                                        |
| logrotate                         | see above section in debian/ directory                                                        |
| postinst                          | see above section in debian/ directory                                                        |
| postinst.constants.db             | top of postinst defining variables for "db" profile apps                                      |
| postinst.constants.web            | top of postinst defining variables for "web" profile apps                                     |
| postinst.configure.db             | main logic during "configure" phase of postinst for "db" apps                                 |
| postinst.configure.web            | main logic during "configure" phase of postinst for "web" apps                                |
| postinst.configure.end.web        | final logic during "configure" phase of postinst for "web" apps                               |
| postrm                            | see above section in debian/ directory                                                        |
| postrm.db                         | extra postrm for "db" apps - just calls dbconfig-common                                       |
| preinst                           | see above section in debian/ directory                                                        |
| preinst.web                       | extra postrm for "web" apps - validates hostname                                              |
| prerm                             | see above section in debian/ directory                                                        |
| prerm.db                          | extra prerm logic for "db" apps                                                               |
| prerm.web                         | prerm logic for "web" apps                                                                    |
| rules                             | see above section in debian/ directory                                                        |
| templates                         | see above section in debian/ directory                                                        |

Building packages
-----------------

### Before building

First bump the debian version. This can be done with dch -i --no-auto-nmu, which will increment the changelog file and open it in your editor to type a commit message into. Just follow the existing format.
Then commit the changelog "git commit debian/changelog; git push", and if necessary, create a tag.

### Building the packages

The packages should be built in a clean checkout of master, not in your working directory. Make sure all external dependencies that need to be bundled have been loaded (submodule's, subversion repositories etc.).

Type "make" in the main directory of your Symfony2 project. This will output the following files:

    ../symfony2-site-foo_0.0.1.dsc
    ../symfony2-site-foo_0.0.1_i386.changes
    ../symfony2-site-foo_0.0.1.tar.gz
    ../symfony2-site-foo-main_0.0.1_all.deb
    ../symfony2-site-foo-static_0.0.1_all.deb

Notice that there is one deb per directory in app/, as well as some extra files that are shared across all packages.

The version number will be slightly different each time, relative to the value in debian/changelog.

### Installing the packages

If you're installing a package that's going to use a database on a remote machine, make sure that the debian priority is low:

    dpkg-reconfigure debconf

Frontend can be set to anything - dialogue is fine. Priority should be low.  This is because of a limitation in dbconfig-common (See: http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=607171)

Before trying to install a package that wants a database (for example symfony2-site-foo-main), the database server must be able to be connected to. The package will not create the database for you.

Note: Theoretically this works with dbconfig-common, and indeed we're using it for other projects, but it hasn't been tested with Symony2.  It may be enough to change the apps.yourapp.dbconfig.create parameter to true in packagemanifest.yml to enable this, but it's not yet tested.

Finally its recommended to setup a debian package repository to distribute the packages. This way on the target servers you just need to setup the custom repository via the following line in its apt sources:

    deb http://packages.example.com/debian/ sid main

and simply type the following command to either install or upgrade:

    apt-get install symfony2-site-foo-APPNAME

### Reconfiguring installed packages

All the values in all dynamic.yml files can be changed by doing:

    dpkg-reconfigure symfony2-site-foo-APPNAME

Credits
=======

This work is based on the original sitepackaging.git found at http://git.catalyst.net.nz/gw?p=sitepackaging.git;a=summary which was originally written by Pete Bulmer at Catalyst IT.  The Symfony2 implementation doesn't have a common ancestor with this, but re-uses some code and is definitely based on the same idea.
