# deb-pkg-builder

Builds debian packages via Docker images/containers.

The assumption when building a package is that git-buildpackage can be used.

To build a package, first set some environmental variables.

```
export DNS=4.4.2.2 
export GUI=true 
export NETWORK=localdockernetwork 
export APTPROXY="aptcacherepository:3142" 
export TESTING=true 
```

All of the options above are not required, but can come in handy during builds.


Next, run the build command.


```
./build.pl $HOME/mycoderepo upstreambranch stablebranch
```

If TEST is set to true, then the script will result in a bash command prompt.  At that point, you can just change directory to where your code is:


```
cd /src/code
```

Once in the directory, feel free to compile the code using whatever the manual build process is.


After the deb package has been compiled, check the ./work directory for the packages that have been built.

