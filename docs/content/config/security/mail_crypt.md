---
title: 'Security | mail_crypt (email/storage encryption)'
---

!!! info
 
    The Mail crypt plugin is used to secure email messages stored in a Dovecot system. Messages are encrypted before written to storage and decrypted after reading. Both operations are transparent to the user.

    In case of unauthorized access to the storage backend, the messages will, without access to the decryption keys, be unreadable to the offending party.

    There can be a single encryption key for the whole system or each user can have a key of their own. The used cryptographical methods are widely used standards and keys are stored in portable formats, when possible.


!!! warning
 
    It's best to choose ONE of the options below early on and carefully, then stick with it. There is no guarantee that switching from Global to User keys will be easy and not result in losing emails.


!!! seealso

    [Official Dovecot documentation](https://doc.dovecot.org/configuration_manual/mail_crypt_plugin/)

---

## Single Encryption Key / Global Method

1. Create `10-custom.conf` and populate it with the following:

    ```
    # Enables mail_crypt for all services (imap, pop3, etc)
    mail_plugins = $mail_plugins mail_crypt
    plugin {
      mail_crypt_global_private_key = </certs/ecprivkey.pem
      mail_crypt_global_public_key = </certs/ecpubkey.pem
      mail_crypt_save_version = 2
    }
    ```

2. Shutdown your mailserver (`docker-compose down`)

3. You then need to [generate your global EC key](https://doc.dovecot.org/configuration_manual/mail_crypt_plugin/#ec-key). We named them `/certs/ecprivkey.pem` and `/certs/ecpubkey.pem` in step #1.

4. The EC key needs to be available in the container. I prefer to mount a /certs directory into the container: 
    ```yaml
    services:
      mailserver:
        image: docker.io/mailserver/docker-mailserver:latest
        volumes:
        . . .
          - ./certs/:/certs
        . . .
    ```

5. While you're editing the `docker-compose.yml`, add the configuration file:
    ```yaml
    services:
      mailserver:
        image: docker.io/mailserver/docker-mailserver:latest
        volumes:
        . . .
          - ./config/dovecot/10-custom.conf:/etc/dovecot/conf.d/10-custom.conf
          - ./certs/:/certs
        . . .
    ```

6. Start the container, monitor the logs for any errors, send yourself a message, and then confirm the file on disk is encrypted:
    ```
    root@ip-xxx:/# xxd /var/mail/xxx/xxx/cur/1625835047.M216159P15117.ip-xxx\,S\=80516\,W\=81800\:2\,S  | head
    00000000: 4352 5950 5445 4403 0702 0000 0002 0000  CRYPTED.........
    00000010: 0143 0609 6086 4801 6503 0401 2e06 0960  .C..`.H.e......`
    00000020: 8648 0165 0304 0201 0000 0800 0000 0113  .H.e............
    00000030: 0102 39f8 ca52 927f ff3d 5be1 0a7e 52e0  ..9..R...=[..~R.
    00000040: 6ae0 e40e 8584 5f89 851b 076c 39c0 14ed  j....._....l9...
    00000050: 8b21 0000 0085 0401 0288 970f d348 6460  .!...........Hd`
    00000060: 29f7 66e4 60f7 57f3 e293 cf1e 4364 7ad7  ).f.`.W.....Cdz.
    00000070: 7d29 0fe5 6cf7 5666 4aa1 b4c9 ddcf 650a  })..l.VfJ.....e.
    00000080: 193b 7f31 072a 28ad d84b c038 ddd2 f060  .;.1.*(..K.8...`
    00000090: 9931 7282 4d4e dd51 e101 9406 d4fc e3d0  .1r.MN.Q........
    ```

This should be the minimum required for encryption of the mail while in storage.


## Encrypted User Keys

1. Create `10-custom.conf` and populate it with the following:

    ```
    mail_attribute_dict = file:%h/Maildir/dovecot-attributes
    mail_plugins = $mail_plugins mail_crypt
    plugin {
      mail_crypt_curve = secp521r1
      mail_crypt_save_version = 2
      mail_crypt_require_encrypted_user_key = yes
    }
    ```

2. Create `auth-passwdfile.inc` and populate it with the following:

    ```
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
    ```

3. Edit the `docker-compose.yml` and add:
    ```yaml
    services:
      mailserver:
        image: docker.io/mailserver/docker-mailserver:latest
        volumes:
        . . .
          - ./config/10-custom.conf:/etc/dovecot/conf.d/10-custom.conf:ro
          - ./config/auth-passwdfile.inc:/etc/dovecot/conf.d/auth-passwdfile.inc:ro
        . . .
    ```

4. Restart your mailserver (`docker-compose down && docker-compose up -d`)

5. You now need to add the encrypted keys for each email account. There are two options:
    
    1. Generate the encrypted key when adding the user for the first time: `./setup.sh email add -g <email>`
    2. Or Generate the encrypted key for an already existing email: `./setup.sh email update -g <email>`
    
    !!! info
    
        When updating a user's password, you need to execute `email update` with `-c`: `./setup.sh email update -c <email>`


6. Start the container, monitor the logs for any errors, send yourself a message, and then confirm the file on disk is encrypted (existing emails are not encrypted):
    ```
    root@ip-xxx:/# xxd /var/mail/xxx/xxx/cur/1625835047.M216159P15117.ip-xxx\,S\=80516\,W\=81800\:2\,S  | head
    00000000: 4352 5950 5445 4403 0702 0000 0002 0000  CRYPTED.........
    00000010: 0143 0609 6086 4801 6503 0401 2e06 0960  .C..`.H.e......`
    00000020: 8648 0165 0304 0201 0000 0800 0000 0113  .H.e............
    00000030: 0102 39f8 ca52 927f ff3d 5be1 0a7e 52e0  ..9..R...=[..~R.
    00000040: 6ae0 e40e 8584 5f89 851b 076c 39c0 14ed  j....._....l9...
    00000050: 8b21 0000 0085 0401 0288 970f d348 6460  .!...........Hd`
    00000060: 29f7 66e4 60f7 57f3 e293 cf1e 4364 7ad7  ).f.`.W.....Cdz.
    00000070: 7d29 0fe5 6cf7 5666 4aa1 b4c9 ddcf 650a  })..l.VfJ.....e.
    00000080: 193b 7f31 072a 28ad d84b c038 ddd2 f060  .;.1.*(..K.8...`
    00000090: 9931 7282 4d4e dd51 e101 9406 d4fc e3d0  .1r.MN.Q........
    ```
