Todos
=====

* Automatically determine the bundles for each kernel so that its no longer necessary to manually configure this.
* Add a way to generate debian packages for Bundles (probably should be done once Symfony2 has come up with a manifest file for Bundles)

Limitations
===========

Single changelog file
---------------------

At the moment in debian, packages that build multiple binary packages from a single source package can only have a single shared changelog. This means the package version numbers move in step. It's not ideal, but the only way to get around it would be to change packaging/maketime.pl to build a debian/ directory and then build the package, for each application, rather than build a single debian/ directory, which is too much work at present.
