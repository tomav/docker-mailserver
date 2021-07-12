# Authentication for passwd-file users. Included from 10-auth.conf.
#
# passwd-like file with specified location.
# <doc/wiki/AuthDatabase.PasswdFile.txt>

passdb {
  driver = passwd-file
  args = scheme=CRYPT username_format=%u /etc/dovecot/userdb
  override_fields = userdb_mail_crypt_private_password=%w userdb_mail_crypt_save_version=2
}

userdb {
  driver = passwd-file
  args = username_format=%u /etc/dovecot/userdb
  default_fields = uid=docker gid=docker home=/var/mail/%d/%u
}
