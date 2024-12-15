# HW 03

### Установка и настройка PostgreSQL
 - создайте виртуальную машину c Ubuntu 20.04/22.04 LTS в ЯО/Virtual Box/докере
 - поставьте на нее PostgreSQL 15 через sudo apt

**Решение:**
[https://www.postgresql.org/download/linux/ubuntu/](https://www.postgresql.org/download/linux/ubuntu/)
ставим по инструкции, т.к. по умолчанию в репозиториях дистрибутива будет какая-то версия, но не все доступные
 - Import the repository signing key:
```
sudo apt install curl ca-certificates
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
```
 - Create the repository configuration file:
```
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
```
 - Update the package lists:
```
sudo apt update
```
 - Смотрим список всех доступных теперь:
```
(base) [developer@postgres-01] ~ $ sudo apt-cache search postgresql-* | grep "Relational Database"
postgresql-10 - The World's Most Advanced Open Source Relational Database
postgresql-11 - The World's Most Advanced Open Source Relational Database
postgresql-12 - The World's Most Advanced Open Source Relational Database
postgresql-13 - The World's Most Advanced Open Source Relational Database
postgresql-14 - The World's Most Advanced Open Source Relational Database
postgresql-15 - The World's Most Advanced Open Source Relational Database
postgresql-16 - The World's Most Advanced Open Source Relational Database
postgresql-17 - The World's Most Advanced Open Source Relational Database
postgresql-9.5 - The World's Most Advanced Open Source Relational Database
postgresql-9.6 - The World's Most Advanced Open Source Relational Database
```
 - Ставим требуемую:
```
sudo apt -y install postgresql-15
```
 - проверьте что кластер запущен через sudo -u postgres pg_lsclusters
```
(base) [developer@postgres-01] ~ $ sudo -u postgres pg_lsclusters
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 online postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
```
 - зайдите из под пользователя postgres в psql и сделайте произвольную таблицу с произвольным содержимым
   `postgres=# create table test(c1 text);`
   `postgres=# insert into test values('1');`
   `\q`
```
(base) [developer@postgres-01] ~ $ sudo su - postgres
[sudo] password for developer: 
postgres@postgres-01:~$ psql
psql (15.10 (Ubuntu 15.10-1.pgdg20.04+1))
Type "help" for help.

postgres=# create table test(c1 text);
CREATE TABLE
postgres=# insert into test values('1');
INSERT 0 1
postgres=# select * from test;
 c1 
----
 1
(1 row)

postgres=# \q
postgres@postgres-01:~$ 
```
 - остановите postgres например через sudo -u postgres pg_ctlcluster 15 main stop
```
(base) [developer@postgres-01] ~ $ sudo -u postgres pg_ctlcluster 15 main stop
Warning: stopping the cluster using pg_ctlcluster will mark the systemd unit as failed. Consider using systemctl:
  sudo systemctl stop postgresql@15-main
(base) [developer@postgres-01] ~ $ sudo -u postgres pg_lsclusters
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 down   postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
```

### Работа с диском
 - создайте новый диск к ВМ размером 10GB
 - добавьте свеже-созданный диск к виртуальной машине - надо зайти в режим ее редактирования и дальше выбрать пункт attach existing disk
 - проинициализируйте диск согласно инструкции и подмонтировать файловую систему, только не забывайте менять имя диска на актуальное, в вашем случае это скорее всего будет /dev/sdb - [https://www.digitalocean.com/community/tutorials/how-to-partition-and-format-storage-devices-in-linux](https://www.digitalocean.com/community/tutorials/how-to-partition-and-format-storage-devices-in-linux)
 - перезагрузите инстанс и убедитесь, что диск остается примонтированным (если не так смотрим в сторону fstab)

**Решение**
В ссылке-подсказке используется работа с блочными устройствами, без привлечения LVM.
В production-ready установках стоит пользоваться LVM для гибкости управления (например, увеличение емкости файловой системы когда выделенного диска станет нехватать).
```
(base) [developer@postgres-01] ~ $ lsblk | grep -v loop
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
vda                       252:0    0   50G  0 disk 
├─vda1                    252:1    0    1M  0 part 
├─vda2                    252:2    0    1G  0 part /boot
└─vda3                    252:3    0   49G  0 part 
  └─ubuntu--vg-ubuntu--lv 253:0    0 48.9G  0 lvm  /
vdb                       252:16   0   20G  0 disk 
```
Наш новый диск - **/dev/vdb**. 
```
(base) [developer@postgres-01] ~ $ sudo parted /dev/vdb mklabel gpt
Information: You may need to update /etc/fstab.
```
Создаем primary раздел
```
(base) [developer@postgres-01] ~ $ sudo parted -a opt /dev/vdb mkpart primary ext4 0% 100%
Information: You may need to update /etc/fstab.
```
Проверяем что он присутствует:
```
(base) [developer@postgres-01] ~ $ lsblk | grep -v loop
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
vda                       252:0    0   50G  0 disk 
├─vda1                    252:1    0    1M  0 part 
├─vda2                    252:2    0    1G  0 part /boot
└─vda3                    252:3    0   49G  0 part 
  └─ubuntu--vg-ubuntu--lv 253:0    0 48.9G  0 lvm  /
vdb                       252:16   0   20G  0 disk 
└─vdb1                    252:17   0   20G  0 part 
```
Создаем файловую систему ext4:
```
(base) [developer@postgres-01] ~ $ sudo mkfs.ext4 -L datapartition /dev/vdb1 
mke2fs 1.45.5 (07-Jan-2020)
Discarding device blocks: done                            
Creating filesystem with 5242368 4k blocks and 1310720 inodes
Filesystem UUID: 172179d8-c1da-4e16-a7e5-c3b068a53ff3
Superblock backups stored on blocks: 
	32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208, 
	4096000

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (32768 blocks): done
Writing superblocks and filesystem accounting information: done   
```
Проверяем наличие метки и сигнатуры файловой системы:
```
(base) [developer@postgres-01] ~ $ sudo lsblk -o NAME,FSTYPE,LABEL,UUID,MOUNTPOINT | grep -v loop
NAME                      FSTYPE      LABEL         UUID                                   MOUNTPOINT
vda                                                                                        
├─vda1                                                                                     
├─vda2                    ext4                      1f8547c4-4374-44b0-9591-f3b2449a7dd5   /boot
└─vda3                    LVM2_member               aXX1S7-9sJV-Oqly-3AnG-tH0L-6hcw-PuDaMI 
  └─ubuntu--vg-ubuntu--lv ext4                      670f6690-bf90-4ef6-b09e-3e9f95ff00cb   /
vdb                                                                                        
└─vdb1                    ext4        datapartition 172179d8-c1da-4e16-a7e5-c3b068a53ff3   
```
Создаем директорию для дальнейшего монтирования в нее файловой системы:
```
(base) [developer@postgres-01] ~ $ sudo mkdir -p /mnt/data
```
Правим `/etc/fstab` для автоматического монтирования при включении системы:
```
(base) [developer@postgres-01] ~ $ sudo vim /etc/fstab
# append
/dev/vdb1       /mnt/data       ext4    defaults        0       2
```
Монтриуем **все** файловые системы, упомянутые в `/etc/fstab` - так убеждаемся что добавленная строка сработает при старте системы
```
(base) [developer@postgres-01] ~ $ sudo mount -a
(base) [developer@postgres-01] ~ $ df -h /mnt/data
Filesystem      Size  Used Avail Use% Mounted on
/dev/vdb1        20G   45M   19G   1% /mnt/data
(base) [developer@postgres-01] ~ $  sync;sync; sudo reboot
```
После перезагрузки проверяем что диск смонтирован и доступен:
```
(base) [developer@postgres-01] ~ $ df -h /mnt/data
Filesystem      Size  Used Avail Use% Mounted on
/dev/vdb1        20G   45M   19G   1% /mnt/data
```
 - сделайте пользователя postgres владельцем /mnt/data - chown -R postgres:postgres /mnt/data/
```
(base) [developer@postgres-01] ~ $ sudo chown -R postgres:postgres /mnt/data/
[sudo] password for developer: 
(base) [developer@postgres-01] ~ $ ls -pla /mnt/data/
total 24
drwxr-xr-x 3 postgres postgres  4096 Dec 15 13:18 ./
drwxr-xr-x 3 root     root      4096 Dec 15 13:19 ../
drwx------ 2 postgres postgres 16384 Dec 15 13:18 lost+found/
```
 - перенесите содержимое /var/lib/postgres/15 в /mnt/data
```
(base) [developer@postgres-01] ~ $ sudo mv /var/lib/postgresql/15 /mnt/data
(base) [developer@postgres-01] ~ $ ls -pla /mnt/data/
total 28
drwxr-xr-x 4 postgres postgres  4096 Dec 15 13:26 ./
drwxr-xr-x 3 root     root      4096 Dec 15 13:19 ../
drwxr-xr-x 3 postgres postgres  4096 Dec 15 12:42 15/
drwx------ 2 postgres postgres 16384 Dec 15 13:18 lost+found/
```
 - попытайтесь запустить кластер - sudo -u postgres pg_ctlcluster 15 main start
 - напишите получилось или нет и почему

После переноса директории командой `mv` исходная директория удаляеся:
```
(base) [developer@postgres-01] ~ $ sudo -u postgres pg_ctlcluster 15 main start
Error: /var/lib/postgresql/15/main is not accessible or does not exist
```
 - задание: найти конфигурационный параметр в файлах раположенных в /etc/postgresql/15/main который надо поменять и поменяйте его
 - напишите что и почему поменяли
```
(base) [developer@postgres-01] ~ $ cat /etc/postgresql/15/main/postgresql.conf | grep -i data_directory
data_directory = '/var/lib/postgresql/15/main'		# use data in another directory
```
Меняем переменную, отвечающую за конфигурацию директории для хранения данных:
```
(base) [developer@postgres-01] ~ $ cat /etc/postgresql/15/main/postgresql.conf | grep -i data_directory
# data_directory = '/var/lib/postgresql/15/main'		# use data in another directory
data_directory = '/mnt/data/15/main/'				# use data in another directory
```
Не забыть добавить переменную в systemd конфиг:
```
vim /lib/systemd/system/postgresql.service
# ...
Environment=PGDATA=/mnt/data/15/main/
# ...
```
И сделать рестарт:
```
systemctl daemon-reload
systemctl start postgresql.service
systemctl status postgresql.service
```
 - попытайтесь запустить кластер - sudo -u postgres pg_ctlcluster 15 main start
 - напишите получилось или нет и почему

Все в порядке:
```
(base) [developer@postgres-01] ~ $ sudo -u postgres pg_ctlcluster 15 main start
Warning: the cluster will not be running as a systemd service. Consider using systemctl:
  sudo systemctl start postgresql@15-main
Removed stale pid file.
(base) [developer@postgres-01] ~ $ sudo -u postgres pg_lsclusters
Ver Cluster Port Status Owner    Data directory     Log file
15  main    5432 online postgres /mnt/data/15/main/ /var/log/postgresql/postgresql-15-main.log
```
 - зайдите через через psql и проверьте содержимое ранее созданной таблицы
```
(base) [developer@postgres-01] ~ $ sudo su - postgres
postgres@postgres-01:~$ psql
psql (15.10 (Ubuntu 15.10-1.pgdg20.04+1))
Type "help" for help.

postgres=# select * from test;
 c1 
----
 1
(1 row)

postgres=# \q
postgres@postgres-01:~$ logout
(base) [developer@postgres-01] ~ $ 
```

### задание со звездочкой *
 - не удаляя существующий инстанс ВМ сделайте новый, поставьте на его PostgreSQL, удалите файлы с данными из /var/lib/postgres, перемонтируйте внешний диск который сделали ранее от первой виртуальной машины ко второй и запустите PostgreSQL на второй машине так чтобы он работал с данными на внешнем диске, расскажите как вы это сделали и что в итоге получилось.

Останавливаем Postgres на текущей виртуалке - для предотвращения изменения данных:
```
(base) [developer@postgres-01] ~ $ sudo -u postgres pg_ctlcluster 15 main stop
(base) [developer@postgres-01] ~ $ sudo -u postgres pg_lsclusters
Ver Cluster Port Status Owner    Data directory     Log file
15  main    5432 down   postgres /mnt/data/15/main/ /var/log/postgresql/postgresql-15-main.log
```
Отмонтируем файловую систему:
```
(base) [developer@postgres-01] ~ $ df -h /mnt/data
Filesystem      Size  Used Avail Use% Mounted on
/dev/vdb1        20G   83M   19G   1% /mnt/data
(base) [developer@postgres-01] ~ $ sudo umount /mnt/data 
(base) [developer@postgres-01] ~ $ lsblk | grep -v loop
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
vda                       252:0    0   50G  0 disk 
├─vda1                    252:1    0    1M  0 part 
├─vda2                    252:2    0    1G  0 part /boot
└─vda3                    252:3    0   49G  0 part 
  └─ubuntu--vg-ubuntu--lv 253:0    0 48.9G  0 lvm  /
vdb                       252:16   0   20G  0 disk 
└─vdb1                    252:17   0   20G  0 part 
(base) [developer@postgres-01] ~ $ 
```
Поднимаем вторую виртуалку, переносим диск на неё
 - т.к. используется ubuntu 20.04 на KVM, рескан портов делать не требуется - диск появится сразу же
```
(base) [developer@postgres-02] ~ $ lsblk | grep -v loop
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
vda                       252:0    0   50G  0 disk 
├─vda1                    252:1    0    1M  0 part 
├─vda2                    252:2    0    1G  0 part /boot
└─vda3                    252:3    0   49G  0 part 
  └─ubuntu--vg-ubuntu--lv 253:0    0 48.9G  0 lvm  /
vdb                       252:16   0   20G  0 disk 
└─vdb1                    252:17   0   20G  0 part 
```
Файловая система там уже есть, достаточно добавить в fstab и смонтировать:
```
(base) [developer@postgres-02] ~ $ sudo mkdir -p /mnt/data
(base) [developer@postgres-02] ~ $ sudo chown -R postgres:postgres /mnt/data/
(base) [developer@postgres-02] ~ $ sudo ls -pla /mnt/data/
total 8
drwxr-xr-x 2 postgres postgres 4096 Dec 15 13:47 ./
drwxr-xr-x 3 root     root     4096 Dec 15 13:47 ../

(base) [developer@postgres-02] ~ $ sudo vim /etc/fstab 
(base) [developer@postgres-02] ~ $ cat /etc/fstab 
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
# / was on /dev/ubuntu-vg/ubuntu-lv during curtin installation
/dev/disk/by-id/dm-uuid-LVM-l71Y58SEfAmFUcn9lfamFTPICCcthnu6aDo5kcMS72od8pQDlGyVuaJwDQ8Xniuv / ext4 defaults 0 1
# /boot was on /dev/vda2 during curtin installation
/dev/disk/by-uuid/1f8547c4-4374-44b0-9591-f3b2449a7dd5 /boot ext4 defaults 0 1
/swap.img	none	swap	sw	0	0
/dev/vdb1	/mnt/data	ext4	defaults	0	2

(base) [developer@postgres-02] ~ $ sudo mount -a
(base) [developer@postgres-02] ~ $ df -h /mnt/data/
Filesystem      Size  Used Avail Use% Mounted on
/dev/vdb1        20G   83M   19G   1% /mnt/data
(base) [developer@postgres-02] ~ $ sudo ls -pla /mnt/data/
total 28
drwxr-xr-x 4 postgres postgres  4096 Dec 15 13:26 ./
drwxr-xr-x 3 root     root      4096 Dec 15 13:47 ../
drwxr-xr-x 3 postgres postgres  4096 Dec 15 12:42 15/
drwx------ 2 postgres postgres 16384 Dec 15 13:18 lost+found/
```
Устанавливаем postgres 15
 - команды такие же как в первых заданиях

Останавливаем кластер для внесения изменений
```
(base) [developer@postgres-02] ~ $ sudo -u postgres pg_lsclusters
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 online postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
(base) [developer@postgres-02] ~ $ sudo -u postgres pg_ctlcluster 15 main stop
Warning: stopping the cluster using pg_ctlcluster will mark the systemd unit as failed. Consider using systemctl:
  sudo systemctl stop postgresql@15-main
(base) [developer@postgres-02] ~ $ sudo -u postgres pg_lsclusters
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 down   postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
```
Правим postgresql.conf
```
(base) [developer@postgres-02] ~ $ cat /etc/postgresql/15/main/postgresql.conf | grep -i data_directory
# data_directory = '/var/lib/postgresql/15/main'		# use data in another directory
data_directory = '/mnt/data/15/main/'				# use data in another directory
```
Не забыть добавить переменную в systemd конфиг:
```
vim /lib/systemd/system/postgresql.service
# ...
Environment=PGDATA=/mnt/data/15/main/
# ...

systemctl daemon-reload
systemctl start postgresql.service
systemctl status postgresql.service
```
Включам postgres, проверяем доступность данных:
```
(base) [developer@postgres-02] ~ $ sudo -u postgres pg_ctlcluster 15 main start
Warning: the cluster will not be running as a systemd service. Consider using systemctl:
  sudo systemctl start postgresql@15-main
(base) [developer@postgres-02] ~ $ sudo -u postgres pg_lsclusters
Ver Cluster Port Status Owner    Data directory     Log file
15  main    5432 online postgres /mnt/data/15/main/ /var/log/postgresql/postgresql-15-main.log


(base) [developer@postgres-02] ~ $ sudo su - postgres
postgres@postgres-02:~$ psql
psql (15.10 (Ubuntu 15.10-1.pgdg20.04+1))
Type "help" for help.

postgres=# select * from test;
 c1 
----
 1
(1 row)

postgres=# \q
postgres@postgres-02:~$ logout
```
Данные доступны.

На будущее: диски лучше делать средствами LVM, и переносить VG - подволяет увеличивать размер файловых систем



