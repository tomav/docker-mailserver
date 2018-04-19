load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

@test "checking process: fail2ban (fail2ban server enabled)" {
  run docker exec mail_fail2ban /bin/bash -c "ps aux --forest | grep -v grep | grep '/usr/bin/python3 /usr/bin/fail2ban-server'"
  assert_success
}

@test "checking fail2ban: localhost is not banned because ignored" {
  run docker exec mail_fail2ban /bin/sh -c "fail2ban-client status postfix-sasl | grep 'IP list:.*127.0.0.1'"
  assert_failure
  run docker exec mail_fail2ban /bin/sh -c "grep 'ignoreip = 127.0.0.1/8' /etc/fail2ban/jail.conf"
  assert_success
}

@test "checking fail2ban: fail2ban-fail2ban.cf overrides" {
  run docker exec mail_fail2ban /bin/sh -c "fail2ban-client get loglevel | grep DEBUG"
  assert_success
}

@test "checking fail2ban: fail2ban-jail.cf overrides" {
  FILTERS=(sshd postfix dovecot postfix-sasl)

  for FILTER in "${FILTERS[@]}"; do
    run docker exec mail_fail2ban /bin/sh -c "fail2ban-client get $FILTER bantime"
    assert_output 1234

    run docker exec mail_fail2ban /bin/sh -c "fail2ban-client get $FILTER findtime"
    assert_output 321

    run docker exec mail_fail2ban /bin/sh -c "fail2ban-client get $FILTER maxretry"
    assert_output 2
  done
}

@test "checking fail2ban: ban ip on multiple failed login" {
  # Getting mail_fail2ban container IP
  MAIL_FAIL2BAN_IP=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' mail_fail2ban)

  # Create a container which will send wrong authentications and should get banned
  docker run --name fail-auth-mailer -e MAIL_FAIL2BAN_IP=$MAIL_FAIL2BAN_IP -v "$(pwd)/test":/tmp/docker-mailserver-test -d tvial/docker-mailserver:testing tail -f /var/log/faillog

  # can't pipe the file as usual due to postscreen. (respecting postscreen_greet_wait time and talking in turn):
  for i in {1,2}; do
    docker exec fail-auth-mailer /bin/bash -c \
    'exec 3<>/dev/tcp/$MAIL_FAIL2BAN_IP/25 && \
    while IFS= read -r cmd; do \
      head -1 <&3; \
      [[ "$cmd" == "EHLO"* ]] && sleep 6; \
      echo $cmd >&3; \
    done < "/tmp/docker-mailserver-test/auth/smtp-auth-login-wrong.txt"'
  done

  sleep 5

  # Checking that FAIL_AUTH_MAILER_IP is banned in mail_fail2ban
  FAIL_AUTH_MAILER_IP=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' fail-auth-mailer)

  run docker exec mail_fail2ban /bin/sh -c "fail2ban-client status postfix-sasl | grep '$FAIL_AUTH_MAILER_IP'"
  assert_success

  # Checking that FAIL_AUTH_MAILER_IP is banned by iptables
  run docker exec mail_fail2ban /bin/sh -c "iptables -L f2b-postfix-sasl -n | grep REJECT | grep '$FAIL_AUTH_MAILER_IP'"
  assert_success
}

@test "checking fail2ban: unban ip works" {
  FAIL_AUTH_MAILER_IP=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' fail-auth-mailer)

  docker exec mail_fail2ban fail2ban-client set postfix-sasl unbanip $FAIL_AUTH_MAILER_IP

  sleep 5

  run docker exec mail_fail2ban /bin/sh -c "fail2ban-client status postfix-sasl | grep 'IP list:.*$FAIL_AUTH_MAILER_IP'"
  assert_failure

  # Checking that FAIL_AUTH_MAILER_IP is unbanned by iptables
  run docker exec mail_fail2ban /bin/sh -c "iptables -L f2b-postfix-sasl -n | grep REJECT | grep '$FAIL_AUTH_MAILER_IP'"
  assert_failure
  docker rm -f fail-auth-mailer
}

@test "checking setup.sh: setup.sh debug fail2ban" {

  run docker exec mail_fail2ban /bin/sh -c "fail2ban-client set dovecot banip 192.0.66.4"
  run docker exec mail_fail2ban /bin/sh -c "fail2ban-client set dovecot banip 192.0.66.5"
  sleep 10
  run ./setup.sh -c mail_fail2ban -p "./test/config" debug fail2ban
  assert_output --regexp "^Banned in dovecot: 192.0.66.5 192.0.66.4.*"
  run ./setup.sh -c mail_fail2ban -p "./test/config" debug fail2ban unban 192.0.66.4
  assert_output --partial "unbanned IP from dovecot: 192.0.66.4"
  run ./setup.sh -c mail_fail2ban -p "./test/config" debug fail2ban
  assert_output --regexp "^Banned in dovecot: 192.0.66.5.*"
  run ./setup.sh -c mail_fail2ban -p "./test/config" debug fail2ban unban 192.0.66.5
  run ./setup.sh -c mail_fail2ban -p "./test/config" debug fail2ban unban
  assert_output --partial "You need to specify an IP address. Run"
}

@test "checking restart of process: fail2ban (fail2ban server enabled)" {
  run docker exec mail_fail2ban /bin/bash -c "pkill fail2ban && sleep 10 && ps aux --forest | grep -v grep | grep '/usr/bin/python3 /usr/bin/fail2ban-server'"
  assert_success
}
