# Compare the cost of setting up a Lambda call site with invokeDynamic (TestD.java),
# vs an equivalent implementation using inner class (TestI.java).
#
# Usage:
#
#    (1) set JAVA_HOME env variable (JDK 9 or later)
#    (2) make run
#    (3) read run.sh to see how you can interpret result.csv
#    (4) read the generated TestI.java and TestL.java

JAVA  = ${JAVA_HOME}/bin/java
JAVAC = ${JAVA_HOME}/bin/javac
JAR   = ${JAVA_HOME}/bin/jar

BUILD_OUTPUT = TestI.jar TestL.jar TestI.jsa TestL.jsa TestLO.jsa
build: ${BUILD_OUTPUT}

TestI.java: gen.sh
	bash gen.sh I >$@

TestL.java: gen.sh
	bash gen.sh L >$@

TestI.jar: TestI.java
	rm -rf classes
	mkdir classes
	${JAVAC} -d classes TestI.java
	${JAR} cf0 $@ -C classes .
	rm -rf classes

TestL.jar: TestL.java
	rm -rf classes
	mkdir classes
	${JAVAC} -d classes TestL.java
	${JAR} cf0 $@ -C classes .
	rm -rf classes

TestI.jsa: TestI.jar
	${JAVA} -Xshare:off -XX:DumpLoadedClassList=TestI.classlist -cp TestI.jar TestI 200
	${JAVA} -Xshare:dump -cp TestI.jar \
		-XX:SharedClassListFile=TestI.classlist -XX:SharedArchiveFile=TestI.jsa 2>&1 | tee $@.log

TestL.jsa: TestL.jar
	${JAVA} -Xshare:off -XX:DumpLoadedClassList=TestL.tmp.classlist -cp TestL.jar TestL 200
	grep -v "_index" TestL.tmp.classlist > TestL.classlist
	${JAVA} -Xshare:dump -cp TestL.jar -Xlog:cds+mh \
		-XX:SharedClassListFile=TestL.classlist -XX:SharedArchiveFile=TestL.jsa 2>&1 | tee $@.log

# TEMP: -XX:+UnlockDiagnosticVMOptions is currently necessary for the generated classlist
#       to contain info about lambdas.
TestLO.jsa: TestL.jar
	${JAVA} -Xshare:off -XX:DumpLoadedClassList=TestLO.classlist -cp TestL.jar -XX:+UnlockDiagnosticVMOptions TestL 200
	${JAVA} -Xshare:dump -cp TestL.jar -Xlog:cds+mh \
		-XX:SharedClassListFile=TestLO.classlist -XX:SharedArchiveFile=TestLO.jsa 2>&1 | tee $@.log

dryrun: ${BUILD_OUTPUT}
	${JAVA} -Xshare:on -cp TestI.jar -XX:SharedArchiveFile=TestI.jsa  TestI 200
	${JAVA} -Xshare:on -cp TestL.jar -XX:SharedArchiveFile=TestL.jsa  TestL 200
	${JAVA} -Xshare:on -cp TestL.jar -XX:SharedArchiveFile=TestLO.jsa TestL 200

run: TestI.jar TestL.jar TestI.jsa TestL.jsa TestLO.jsa
	bash run.sh

clean:
	rm -rf classes *~ TestI.java TestL.java *.jar *.class *.jsa *.classlist *.log result.*

info:
	@echo "JAVA  = ${JAVA}"
	@echo "JAVAC = ${JAVAC}"
