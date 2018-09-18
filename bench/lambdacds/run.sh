# Compare the cost of setting up a Lambda call site (TestL.java),
# vs an equivalent implementation using inner class (TestI.java).
#
# The output is in result.csv. Open this in your spreadsheet for further analysis,
# such as calculating the cost of each call site.

if [[ "$JAVA" = "" ]]; then
    JAVA=$JAVA_HOME/bin/java
fi


# i   = inner class, cds disabled
# is  = inner class, cds enabled
# l   = lambda, cds disabled
# ls  = lambda, cds enabled, baseline
# lso = lambda, cds enabled, optimized 

if [[ "$MODES" = "" ]]; then
    MODES="i is l ls lso"
fi

if test "$REPEAT" = ""; then
    REPEAT=50
fi

if test "$INSTANCES" = ""; then
    INSTANCES="0 1 0 1 5 25 50 100"
fi

if test "$NOSYNC" != ""; then
    echo "Syncing and sleeping for 4 seconds ..."
    sync
    sleep 2
    sync
    sleep 2
fi

declare -A infos
declare -A names
declare -A sharing
declare -A jsa

infos[i]='Inner class, no CDS'
infos[is]='Inner class, with CDS'
infos[l]='Lambda, no CDS'
infos[ls]='Lambda, with CDS, (baseline)'
infos[lso]='Lambda, with CDS, (optimized)'


names[i]=TestI
names[is]=TestI
names[l]=TestL
names[ls]=TestL
names[lso]=TestL

sharing[i]=off
sharing[is]=on
sharing[l]=off
sharing[ls]=on
sharing[lso]=on

jsa[i]=
jsa[is]=-XX:SharedArchiveFile=TestI.jsa
jsa[l]=
jsa[ls]=-XX:SharedArchiveFile=TestL.jsa
jsa[lso]=-XX:SharedArchiveFile=TestLO.jsa


result=result-$(date +%Y%m%d-%H%M%S).csv
cat <<EOF | tee $result
Benchmark executed on $(uname -a) at $(date)
JAVA_HOME=$JAVA_HOME
JAVA_VERSION=$($JAVA -Xinternalversion)

Legend:
EOF

for m in $MODES; do
    echo "$(printf %3s $m),=,${infos[$m]}" | tee -a $result
done

OUT="  #,"
STDEV=",,,"
ochars=0
otail=
for m in $MODES; do
    OUT="$OUT,$(printf %8s $m)"    
    STDEV="$STDEV,$(printf "%5s" $m)"
    ochars=$(expr $ochars + 8)
    otail="${otail},"
done
echo "   ,,$(printf %-${ochars}s ELAPSED)${otail},,,STDEV" | tee -a $result
echo "${OUT}${STDEV}" | tee -a $result

for i in $INSTANCES; do
    OUT="$(printf %3d $i),"
    STDEV=",,,"

    for m in $MODES; do
        name=${names[$m]}
        xshare=${sharing[$m]}
        archive=${jsa[$m]}

        log=${m}-${i}.bench.log

        (set -x; perf stat -r $REPEAT $JAVA -Xshare:$xshare -cp ${name}.jar \
            $archive $name $i 2>&1)  | cat > $log

        time=$(cat $log | grep 'seconds time elapsed' | sed -e 's/ seconds time.*//g' | xargs echo)
        time=$(echo | awk "{print $time * 1000}")
        time=$(printf %8.4f $time)
        stdev=$(cat $log | grep 'seconds time elapsed' | sed -e 's/.*[+][-]*//' -e 's/%.*//' | xargs echo)
        stdev=$(printf %4.1f%% $stdev)
        OUT="$OUT,$time"
        STDEV="$STDEV,${stdev}"
    done

    echo "${OUT}${STDEV}" | tee -a $result
done

(set -x; cat $result)



