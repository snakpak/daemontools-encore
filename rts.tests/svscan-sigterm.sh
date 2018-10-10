# TODO:
#   * how do we know logs stop *after* main?
#
#   * if logging with multilog (which exits at end of stdin), will a new
#     multilog be created after the main supervise exits, but before the
#     log supervise is signaled? if so, can we avoid it?
#

# svc0 - no log
# svc1 - svscan-managed log
# svc2 - supervise-managed log

echo '--- svscan handles sigterm'
echo

rm -rf test.boot
mkdir test.boot          || die "Could not create test.boot"
mkdir test.boot/service  || die "Could not create test.boot/service"
mkdir test.boot/svc0     || die "Could not create test.boot/svc0"
mkdir test.boot/svc1     || die "Could not create test.boot/svc1"
mkdir test.boot/svc1/log || die "Could not create test.boot/svc1/log"
mkdir test.boot/svc2     || die "Could not create test.boot/svc2"

cd test.boot || die "Could not change to test.boot"

ln -s ../svc0 service || die "Could not link svc0"
ln -s ../svc1 service || die "Could not link svc1"
ln -s ../svc2 service || die "Could not link svc2"


catexe svscan <<'EOF' || die "Could not create svscan wrapper"
#!/bin/sh
PATH=`echo $PATH | cut -d':' -f2-`
exec env - PATH=$PATH svscan $@ &
echo $! > svscan.pid
EOF

## this doesnt work. get the pid in svscanboot instead.
#catexe readproctitle <<'EOF' || die "Could not create readproctitle wrapper"
##!/bin/sh
#exec >readproctitle.log
#exec 2>&1
#PATH=`echo $PATH | cut -d':' -f2-`
#exec env - PATH=$PATH readproctitle $@ &
#echo $! > test.boot/readproctitle.pid
#EOF

test -x ../../svscanboot || die "Could not find svscanboot source"
sed -r                                      \
  -e 's,PATH=/,PATH=.:..:../..:../../..:/,' \
  -e 's,^exec 2?>.+,,'                      \
  -e 's,/command/svc -dx .+,,g'             \
  -e 's,/?service,service,g'                \
  -e 's,readproctitle..*,& \& \
,'                                          \
  -e '$a\
echo $! > readproctitle.pid'                \
  -e '$a\
wait'                                       \
< ../../svscanboot                          \
| catexe svscanboot
test -x svscanboot || die "Could not create svscanboot stub"

makefifo svc0.ready
catexe svc0/run <<'EOF' || die "Could not create svc0/run script"
#!/bin/sh
echo svc0 ran                          >> ../svc0.log
exec ../../../sleeper -w ../svc0.ready >> ../svc0.log
EOF

makefifo svc1-main.ready
catexe svc1/run <<'EOF' || die "Could not create svc1/run script"
#!/bin/sh
echo svc1-main ran                          >> ../svc1-main.log
exec ../../../sleeper -w ../svc1-main.ready >> ../svc1-main.log
EOF

makefifo svc1-log.ready
catexe svc1/log/run <<'EOF' || die "Could not create svc1/log/run script"
#!/bin/sh
echo svc1-log ran                                >> ../../svc1-log.log
exec ../../../../sleeper -w ../../svc1-log.ready >> ../../svc1-log.log
EOF

makefifo svc2-main.ready
catexe svc2/run <<'EOF' || die "Could not create svc2/run script"
#!/bin/sh
echo svc2-main ran                          >> ../svc2-main.log
exec ../../../sleeper -w ../svc2-main.ready >> ../svc2-main.log
EOF

makefifo svc2-log.ready
catexe svc2/log <<'EOF' || die "Could not create svc2/log script"
#!/bin/sh
echo svc2-log ran                          >> ../svc2-log.log
exec ../../../sleeper -w ../svc2-log.ready >> ../svc2-log.log
EOF


timed_read() {
  for i in 10 9 8 7 6 5 4 3 2 1 0; do
    if [ -f $1 ]; then
      head -n 1 $1
      break
    fi
    if [ $i -eq 0 ]; then
      echo 0
      break
    fi
    sleep 1
  done
}

echo '--- svscanboot started'
./svscanboot service > svscanboot.log 2>&1 &
svscanbootpid=$!
if [ "$svscanbootpid" != "0" ]; then
  echo ok
fi
echo

echo '--- svscan started'
svscanpid=`timed_read svscan.pid`
if [ "$svscanpid" != "0" ]; then
  echo ok
fi
echo

echo '--- readproctitle started'
readproctitlepid=`timed_read readproctitle.pid`
if [ "$readproctitlepid" != "0" ]; then
  echo ok
fi
echo


check_pid_sanity() {
  if [ `echo $1 | grep -E '^[1-9][0-9]{0,4}$' | wc -l` != "1" ] \
    || [ $1 -le 1 ]                                             \
    || [ $1 -ge 99999 ]
  then
    echo 0
  else
    echo $1
  fi
}

echo '--- svscanboot pid looks sane'
svscanbootpid=`check_pid_sanity $svscanbootpid`
if [ "$svscanbootpid" != "0" ]; then
  echo ok
fi
echo

echo '--- svscan pid looks sane'
svscanpid=`check_pid_sanity $svscanpid`
if [ "$svscanpid" != "0" ]; then
  echo ok
fi
echo

echo '--- readproctitle pid looks sane'
readproctitlepid=`check_pid_sanity $readproctitlepid`
if [ "$readproctitlepid" != "0" ]; then
  echo ok
fi
echo


echo '--- svscanboot is running'
if kill -0 $svscanbootpid; then
  echo ok
else
  svscanbootpid=0
fi
echo

echo '--- svscan is running'
if kill -0 $svscanpid; then
  echo ok
else
  svscanpid=0
fi
echo

echo '--- readproctitle is running'
if kill -0 $readproctitlepid; then
  echo ok
else
  readproctitlepid=0
fi
echo

echo '--- supervise svc0 is running'
svok svc0 && echo ok
echo

echo '--- supervise svc1 is running'
svok svc1 && echo ok
echo

echo '--- supervise svc1/log is running'
svok svc1/log && echo ok
echo

echo '--- supervise svc2 is running'
svok svc2 && echo ok
echo


echo '--- svc0.log readable'
cat svc0.ready
echo

echo '--- svc1-main.log readable'
cat svc1-main.ready
echo

echo '--- svc1-log.log readable'
cat svc1-log.ready
echo

echo '--- svc2-main.log readable'
cat svc2-main.ready
echo

echo '--- svc2-log.log readable'
cat svc2-log.ready
echo


echo '--- sigterm sent'
if [ "$svscanpid" != "0" ] && kill -TERM $svscanpid; then
  echo ok
fi
echo


timed_stop() {
  if [ $1 -ne 0 ]; then
    for i in 10 9 8 7 6 5 4 3 2 1 0; do
      if kill -0 $1 2>/dev/null; then
        if [ $i -eq 0 ]; then
          kill -HUP $1
          break
        fi
        sleep 1
      else
        echo ok
        break
      fi
    done
  fi
}

echo '--- svscan is stopped'
timed_stop $svscanpid
echo

echo '--- readproctitle is stopped'
timed_stop $readproctitlepid
echo

echo '--- svscanboot is stopped'
timed_stop $svscanbootpid
echo


timed_down() {
  for i in 10 9 8 7 6 5 4 3 2 1 0; do
    if svok $1; then
      svc -dx $1
      if [ $i -eq 0 ]; then
        break
      fi
      sleep 1
    else
      echo ok
      break
    fi
  done
}

echo '--- supervise svc0 is down'
timed_down svc0
echo

echo '--- supervise svc1 is down'
timed_down svc1
echo

echo '--- supervise svc1/log is down'
timed_down svc1/log
echo

echo '--- supervise svc2 is down'
timed_down svc2
echo


echo '--- svscanboot log'
cat svscanboot.log
echo

echo '--- svc0 log'
cat svc0.log
echo

echo '--- svc1 main log'
cat svc1-main.log
echo

echo '--- svc1 log log'
cat svc1-log.log
echo

echo '--- svc2 main log'
cat svc2-main.log | uniq
echo

echo '--- svc2 log log'
cat svc2-log.log
echo


# just in case
svc -dx svc0 svc1 svc1/log svc2 2>/dev/null

cd $TOP

