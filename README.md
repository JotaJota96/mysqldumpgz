# MySQL Dump Automation Script

This bash script automates the process of creating *MySQL* database backups using the `mysqldump` command, naming the files with the date and compressing them.

```diff
-$ sudo mysqldump -u root -p --databases MyDatabase > 20221231.sql
-$ sudo chown user:user 20221231.sql
-$ gzip 20221231.sql
-$ mv 20221231.sql.gz ~/dumps/
+$ mysqldumpgz -m
```

## How it works

The script uses the configuration defined in the constants in the `mysqldumpgz-config.sh` file, and it verifies that the file names are valid and can be created.

The `mysqldump` command is used to extract a dump. The file name is generated using the current date and a customizable suffix. The extraction is executed in the background, so the script can extract multiple databases at the same time.

Backups are compressed with the `gzip` command and stored in a default folder. In case a file name was specified when running the script, the file will be saved with that name in the current folder. Finally, the owner and group of the file are changed to the specified in the configuration.

## Installation

To install the script, you can copy it to a folder and add it to your `PATH` environment variable.

```bash
cd ~/your-scripts-folder
wget https://raw.github.com/JotaJota96/mysqldumpgz/master/mysqldumpgz.sh
wget https://raw.github.com/JotaJota96/mysqldumpgz/master/mysqldumpgz-config.sh
chmod 600 mysqldumpgz-config.sh 
chmod 700 mysqldumpgz.sh
mv mysqldumpgz.sh mysqldumpgz
```

In the last step you can customize the name of the script if you want.

If your scripts folder is not in your `PATH` environment variable, you can add it by executing the following command:

```bash
echo "export PATH=\${PATH}:${HOME}/your-scripts-folder" >> ~/.bashrc
source ~/.bashrc
```

Execute `mysqldumpgz --check` to verify that the script is installed correctly:

## Configuration

To configure the script, it is necessary to modify the values of the constants defined in the `mysqldumpgz-config.sh` file.

- `DB_KEYS`: Keys to identify the databases the script can work with. It is used within the script to be able to access the values specified in `DB_CONFIG`.
- `DB_CONFIG`: Contains information related to each database that the script can work with.

  - `short_flag` and `long_flag`: Flags to be used in the command line arguments to specify the database to extract.
  - `show_name`: Name that is shown in the logs
  - `db_name`: Database name
  - `file_suffix`: File suffix

You can add as many databases as you want, as long as you add the corresponding key to the `DB_KEYS` constant.

You can also modify the following constants:

- `DEFAULT_DATE_FORMAT`: Date format used to generate the file name.
- `DEFAULT_DUMP_FOLDER`: Folder where the backups will be stored.
- `DEFAULT_DB_USER`: Database user used to extract the backups (Password will be required when executing the script)
- `DEFAULT_SYS_USER`: User that will own the backups.
- `DEFAULT_SYS_GROUP`: Group that will own the backups.
- `REQUIRE_ROOT`: If `true`, the script will require root privileges to execute.

## Usage

### Available arguments

- `--check`: Checks if the commands used by the script are available.
- `--config`: Shows the configuration.
- `-h`, `--help`: Shows this help.
- `-s`, `--simulate`: Shows the commands that extract the dump but does not execute them.
- `-a`, `--all`: Extracts all the databases.

If there are configured databases, you can use your short or long flag to extract the corresponding database.

### Examples of use

- Extract all the database dumps and store them in the default output files:

  ```bash
  ./mysqldumpgz.sh -a
  ```

- Show the commands that would be executed (`-s`) to extract a specific database (`-m`), but do not execute them:

  ```bash
  ./mysqldumpgz.sh -s -m
  ```

  It will show something like:

  ```bash
  Commands to execute to extract the dump of my_database:
  $ mysqldump -u root -p****** --databases my_database > /home/user/dumps/2023-01-09_myDB.sql
  $ gzip /home/user/dumps/2023-01-09_myDB.sql
  $ chown user:user /home/user/dumps/2023-01-09_myDB.sql.gz
  ```

- Extract two databases (`-m` and `-o`) specifying the output file name for each one:

  ```bash
  ./mysqldumpgz.sh -m myDB.sql -o myOtherDB.sql
  ```

## Related

It would be recommended to create a user with the minimum permissions to extract the database dumps. The following are the steps to do so:

1. Enter the MySQL console.

    ```bash
    mysql -u root -p
    ```

2. Create a user with its password.

    ```mysql
    CREATE USER 'my_dump_user'@'localhost' IDENTIFIED BY '1234';
    ```

3. Grant the user the minimum permissions to extract the database dumps.

    ```mysql
    GRANT select, lock tables, show view ON my_database.* TO 'my_dump_user'@'localhost';

    FLUSH PRIVILEGES;
    ```

4. Verify that the user has the correct permissions.

    ```mysql
    SHOW GRANTS FOR my_dump_user@localhost;
    ```
