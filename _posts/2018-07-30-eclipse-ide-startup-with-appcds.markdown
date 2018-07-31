---
layout: post
title:  "Improve Eclipse IDE Startup with CDS"
date:   2018-07-30 11:00:00 -0800
categories: jekyll update
---

Since the Eclipse IDE loads a lot of classes during start-up, it seems like CDS
can help to make it start faster.

First, let's install Eclipse. I download the "Photon R" version of "Eclipse IDE for Java Developers"
from [here](http://www.eclipse.org/downloads/packages/release/photon/r/eclipse-java-photon-r), and run it like this:

```
tar zxf eclipse-java-photon-R-linux-gtk-x86_64.tar.gz
cd eclipse
java -jar ./plugins/org.eclipse.equinox.launcher_1.5.0.v20180512-1130.jar \
    -Xlog:class+load=debug:file=classload.log \
    -debug
```

When running with the `-debug` option, Eclipse prints out how long it takes to
start-up the IDE, like this:

```
Starting application: 2719
...
Application Started: 9480
```

From the `classload.log` file, we can see that a lot of the classes are loaded by custom class loaders:



| Loader        | Number of classes |
| ------------- | --------:|
| Bootstrap     |    2759  |
| Platform      |      77  |
| Application   |       6  |
| Custom Loaders|  **9969**|
| Total         |   12811  | 

<br>

The JDK doesn't come with tooling for CDS support for custom loaders, so
I used Volker Simonis' [cl4cds](https://github.com/simonis/cl4cds)
to create a class list (*see note below*):

```
# Dry run to collect class loading log:
java -Xshare:off -Xlog:class+load=debug:file=classload.log \
     -jar ./plugins/org.eclipse.equinox.launcher_1.5.0.v20180512-1130.jar \
     -debug

# Convert the log file to a CDS class list
java -cp ~/cl4cds/classes io.simonis.cl4cds classload.log eclipse.classlist

# Create CDS archive for Eclipse
java -Xshare:dump \
     -cp  ./plugins/org.eclipse.equinox.launcher_1.5.0.v20180512-1130.jar \
     -XX:SharedClassListFile=eclipse.classlist \
     -XX:SharedArchiveFile=eclipse.jsa

# Run Eclipse with the CDS archive file 
java -Xshare:auto -XX:SharedArchiveFile=eclipse.jsa \
     -jar ./plugins/org.eclipse.equinox.launcher_1.5.0.v20180512-1130.jar \
     -debug
```

With a little bit of automation, I ran the start-up for 40 times each with the latest JDK 12
repo, with and without CDS:

|Mode        |Start-up time(ms)|
|------------|----------------:|
|-Xshare:off |    5820 |
|-Xshare:auto|    4753 |
|Improvement |  **1067**|

<br>

This shows that CDS can provide significant improvement for apps that load a large number
of classes via custom loaders. However, the current usage model is very difficult.

Ideally, we should make this completely automatic, perhaps something like the following, which
automatically creates a CDS archive and populate it with all classes loaded by the app:

```
java -Xshare:autocreate \
     -jar ./plugins/org.eclipse.equinox.launcher_1.5.0.v20180512-1130.jar
```

We will try to implement this in the following REFs for the JDK:

  * [JDK-8207812](https://bugs.openjdk.java.net/browse/JDK-8207812) - Support dynamic archiving classes
  * [JDK-8192921](https://bugs.openjdk.java.net/browse/JDK-8192921) - Improve CDS support for custom loaders


# Note

I had to use [this patch]({{ site.url }}/misc/cl4cds.diff.txt) to make
cl4cds work with Eclipse and the latest JDK repo (JDK 12)

