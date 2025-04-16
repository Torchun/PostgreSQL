# Создание и тестирование высоконагруженного отказоустойчивого кластера PostgreSQL на базе Patroni
- реализовать свой миникластер на 3 ВМ.
<br>

### Создаем 3 виртуалки

| имя ВМ  | IP            | port | 
|---------|---------------|------|
| node-00 | 172.17.210.17 | 5432 |
| node-01 | 172.17.210.18 | 5432 |
| node-02 | 172.17.210.19 | 5432 |
| haproxy | 172.17.210.20 | 5432 |

Ссылки в помощь:
 - [https://stormatics.tech/blogs/setting-up-a-high-availability-3-node-postgresql-cluster-with-patroni-on-ubuntu-24-04](https://stormatics.tech/blogs/setting-up-a-high-availability-3-node-postgresql-cluster-with-patroni-on-ubuntu-24-04)
 - [https://medium.com/@yaseminbsra.sergen/postgresql-with-patroni-high-availability-and-backup-integration-1fd97bffbac1](https://medium.com/@yaseminbsra.sergen/postgresql-with-patroni-high-availability-and-backup-integration-1fd97bffbac1)
 - С осторожностью, вендор: [https://docs.percona.com/postgresql/16/solutions/ha-setup-apt.html#configure-haproxy](https://docs.percona.com/postgresql/16/solutions/ha-setup-apt.html#configure-haproxy)
 - [https://docs.microfocus.com/doc/401/25.2/hasqlpatroni](https://docs.microfocus.com/doc/401/25.2/hasqlpatroni)
 - Когда хочется всё в докерах: [https://github.com/patroni/patroni/blob/master/docker-compose.yml](https://github.com/patroni/patroni/blob/master/docker-compose.yml)

### ETCD

 - Инструкция: [https://etcd.io/docs/v2.3/docker_guide/](https://etcd.io/docs/v2.3/docker_guide/)
 - Не забыть переключиться на свежую версию: [https://etcd.io/docs/v3.5/op-guide/container/](https://etcd.io/docs/v3.5/op-guide/container/)
 - Не забыть в `patroni.yml` указать версию протокола `etcd3` (цифра **3** указывает на v3)
 - Когда хочется в докере: [https://github.com/guessi/docker-compose-etcd/blob/master/docker-compose.yml](https://github.com/guessi/docker-compose-etcd/blob/master/docker-compose.yml)

На каждой виртуалке:
```commandline
mkdir -p cluster/etcd
chmod 777 cluster/etcd
cd cluster
```
Скопируем в директорию `~/cluster` соответствующий ноде `docker-compose.node-0*.yaml` и запустим:
```commandline
docker-compose -f docker-compose.node-0*.yaml up -d
```
Проверяем что кластер `etcd` работает штатно:
```commandline
$ docker run --rm -ti --net=host quay.io/coreos/etcd:v3.5.16 etcdctl --endpoints=http://172.17.210.17:2379,http://172.17.210.18:2379,http://172.17.210.19:2379 -w table member list 
+------------------+---------+--------+---------------------------+---------------------------+------------+
|        ID        | STATUS  |  NAME  |        PEER ADDRS         |       CLIENT ADDRS        | IS LEARNER |
+------------------+---------+--------+---------------------------+---------------------------+------------+
| 3184884b22640f76 | started | etcd-1 | http://172.17.210.17:2380 | http://172.17.210.17:2379 |      false |
| 65a759fea614990b | started | etcd-3 | http://172.17.210.19:2380 | http://172.17.210.19:2379 |      false |
| 9ac617e0ebf5480d | started | etcd-2 | http://172.17.210.18:2380 | http://172.17.210.18:2379 |      false |
+------------------+---------+--------+---------------------------+---------------------------+------------+

$ docker run --rm -ti --net=host quay.io/coreos/etcd:v3.5.16 etcdctl --endpoints=http://172.17.210.17:2379,http://172.17.210.18:2379,http://172.17.210.19:2379 -w table endpoint status
+---------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|         ENDPOINT          |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+---------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| http://172.17.210.17:2379 | 3184884b22640f76 |  3.5.16 |   20 kB |      true |      false |         2 |          9 |                  9 |        |
| http://172.17.210.18:2379 | 9ac617e0ebf5480d |  3.5.16 |   20 kB |     false |      false |         2 |          9 |                  9 |        |
| http://172.17.210.19:2379 | 65a759fea614990b |  3.5.16 |   20 kB |     false |      false |         2 |          9 |                  9 |        |
+---------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
```
Так же доступен endpoint с метриками: `http://172.17.210.17:2379/metrics`

### PostgreSQL

Установка постгреса как на обычную ОС. На каждую из трех нод.

Дополнительно, сделаем симлинк:
```commandline
sudo ln -s /usr/lib/postgresql/15/bin/* /usr/sbin/
```

Результат:
```commandline
(base) [developer@node-02] cluster $ pg_lsclusters 
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 down   postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
```

### Patroni

[https://patroni.readthedocs.io/en/latest/](https://patroni.readthedocs.io/en/latest/)

Устанавливаем требуемые пакеты, т.к. это `python`-скрипты:
```commandline
sudo apt-get install net-tools python3-pip python3-dev libpq-dev python3-venv -y
```

Patroni будет устанавливаться из-под пользоватя `postgres`:
```commandline
sudo su postgres
cd $HOME
python3 -m venv patroni-packages
source patroni-packages/bin/activate
pip3 install --upgrade setuptools pip
pip install psycopg[binary] patroni python-etcd
cd $HOME/patroni-packages
touch patroni.yml
mkdir -p data
chmod 700 data
```

Конфиг для patroni для каждой ноды лежит в файлах `./node-0*/patroni.yml`

Дополнительно пропишем `systemd` unit:
```commandline
sudo touch /etc/systemd/system/patroni.service
```
```commandline
[Unit]
Description=High availability PostgreSQL Cluster
After=syslog.target network.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/var/lib/postgresql/patroni-packages/bin/patroni /var/lib/postgresql/patroni-packages/patroni.yml
KillMode=process
TimeoutSec=30
Restart=no

[Install]
WantedBy=multi-user.target
```

Теперь стартуем patroni кластер на каждой ноде

```commandline
sudo systemctl enable --now patroni
sudo systemctl restart patroni
```

И проверяем статус кластера:
```commandline
/var/lib/postgresql/patroni-packages/bin/patronictl -c /var/lib/postgresql/patroni-packages/patroni.yml list
```
```commandline
+ Cluster: postgres (7493617658843587548) ------+----+-----------+
| Member  | Host          | Role    | State     | TL | Lag in MB |
+---------+---------------+---------+-----------+----+-----------+
| node-00 | 172.17.210.17 | Replica | streaming |  3 |         0 |
| node-01 | 172.17.210.18 | Leader  | running   |  3 |           |
| node-02 | 172.17.210.19 | Replica | streaming |  3 |         0 |
+---------+---------------+---------+-----------+----+-----------+
```

Либо та же команда из-под пользователя `postgres` с активированным `venv`:
```commandline
sudo su postgres
source patroni-packages/bin/activate
patronictl -c patroni-packages/patroni.yml list
```
```commandline
+ Cluster: postgres (7493617658843587548) ------+----+-----------+
| Member  | Host          | Role    | State     | TL | Lag in MB |
+---------+---------------+---------+-----------+----+-----------+
| node-00 | 172.17.210.17 | Replica | streaming |  3 |         0 |
| node-01 | 172.17.210.18 | Leader  | running   |  3 |           |
| node-02 | 172.17.210.19 | Replica | streaming |  3 |         0 |
+---------+---------------+---------+-----------+----+-----------+
```

### HAProxy

[https://www.haproxy.org/](https://www.haproxy.org/)

Установка на ноде `haproxy`, `172.17.210.20`:
```commandline
sudo apt-get install haproxy -y
sudo vim /etc/haproxy/haproxy.cfg
```

Конфиг `sudo vim /etc/haproxy/haproxy.cfg`:
```commandline
global  
        maxconn 100
        log     127.0.0.1 local2
defaults
        log global
        mode tcp
        retries 2
        timeout client 30m
        timeout connect 4s
        timeout server 30m
        timeout check 5s
listen stats
    mode http
    bind *:7000
    stats enable
    stats uri /
listen postgres
    bind *:5432
    option httpchk
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server node-00 172.17.210.17:5432 maxconn 100 check port 8008
    server node-01 172.17.210.18:5432 maxconn 100 check port 8008
    server node-02 172.17.210.19:5432 maxconn 100 check port 8008
```

Включение и рестарт:
```commandline
sudo systemctl enable haproxy
sudo systemctl restart haproxy
sudo systemctl status haproxy
```

Проверяем:
```commandline
(base) [developer@haproxy] ~ $ journalctl -u haproxy

Apr 15 19:24:45 haproxy systemd[1]: Starting HAProxy Load Balancer...
Apr 15 19:24:45 haproxy haproxy[2622]: [NOTICE] 104/192445 (2622) : New worker #1 (2624) forked
Apr 15 19:24:45 haproxy systemd[1]: Started HAProxy Load Balancer.
Apr 15 19:24:45 haproxy haproxy[2624]: [WARNING] 104/192445 (2624) : Server postgres/node-00 is DOWN, reason: Layer7 wrong status, code: 503, info: "HTTP status check returned code <3C>503<3E>", check duration: 1ms. 2 active and 0 backup servers left. 0 sessions active, 0 re>
Apr 15 19:24:47 haproxy haproxy[2624]: [WARNING] 104/192447 (2624) : Server postgres/node-02 is DOWN, reason: Layer7 wrong status, code: 503, info: "HTTP status check returned code <3C>503<3E>", check duration: 1ms. 1 active and 0 backup servers left. 0 sessions active, 0 re>
```

Сверяемся с patroni:
```commandline
+ Cluster: postgres (7493617658843587548) ------+----+-----------+
| Member  | Host          | Role    | State     | TL | Lag in MB |
+---------+---------------+---------+-----------+----+-----------+
| node-00 | 172.17.210.17 | Replica | streaming |  3 |         0 |
| node-01 | 172.17.210.18 | Leader  | running   |  3 |           |
| node-02 | 172.17.210.19 | Replica | streaming |  3 |         0 |
+---------+---------------+---------+-----------+----+-----------+
```

Все запросы идут на master ноду, которая сейчас и помечена активной.


# Тестирование

Тестируем переключение под нагрузкой.
> Нагрузку генерируем утилитой `pgbench` на локальной машине

Подготовим таблицы:
```commandline
pgbench -i postgres -h 172.17.210.20 -p 5432 -U postgres 
```
```commandline
postgres=# \dt+
                          List of relations
 Schema |       Name       | Type  |  Owner   |  Size   | Description 
--------+------------------+-------+----------+---------+-------------
 public | pgbench_accounts | table | postgres | 13 MB   | 
 public | pgbench_branches | table | postgres | 40 kB   | 
 public | pgbench_history  | table | postgres | 0 bytes | 
 public | pgbench_tellers  | table | postgres | 40 kB   | 
(4 rows)
```

Генерируем нагрузку в 32 потока, с отчетом казжые 60 секунд, в течении 30 минут:
```commandline
pgbench -c 8 -P 60 -T 1800 postgres -h 172.17.210.20 -p 5432 -U postgres
```
Виртуальные машины созданы на шпиндельных дисках специально, чтобы увидеть практические пределы без дополнительного тюнинга.

### План тестирования
 - 10 минут подается нагрузка через `HA Proxy`
 - выключается мастер-нода, нагрузка продолжается в течении 5 минут
 - выключается новая мастер-нода, остается единственная в кластере
 - включаются обе выключенные ноды, нагрузка подается еще 10 минут

# Результаты

Исходное состояние кластера:
```commandline
$ patronictl -c patroni-packages/patroni.yml list
+ Cluster: postgres (7493617658843587548) ------+----+-----------+
| Member  | Host          | Role    | State     | TL | Lag in MB |
+---------+---------------+---------+-----------+----+-----------+
| node-00 | 172.17.210.17 | Leader  | running   |  7 |           |
| node-01 | 172.17.210.18 | Replica | streaming |  7 |         0 |
| node-02 | 172.17.210.19 | Replica | streaming |  7 |         0 |
+---------+---------------+---------+-----------+----+-----------+
```

Потеря первой ноды `node-00` - выключение VM, сессии обрываются:
```commandline
Wed Apr 16 14:51:04 UTC 2025

+ Cluster: postgres (7493617658843587548) ------+----+-----------+
| Member  | Host          | Role    | State     | TL | Lag in MB |
+---------+---------------+---------+-----------+----+-----------+
| node-00 | 172.17.210.17 | Replica | stopped   |    |   unknown |
| node-01 | 172.17.210.18 | Replica | streaming |  8 |         0 |
| node-02 | 172.17.210.19 | Leader  | running   |  8 |           |
+---------+---------------+---------+-----------+----+-----------+
```

**При потере больше 50% нод (2n+1) кластер перестает работать, PostgreSQL недоступен до формирования кворума**

Состояние кластера в момент до включения ноды:
```commandline
Wed Apr 16 14:55:08 UTC 2025

+ Cluster: postgres (7493617658843587548) ------+----+-----------+
| Member  | Host          | Role    | State     | TL | Lag in MB |
+---------+---------------+---------+-----------+----+-----------+
| node-01 | 172.17.210.18 | Replica | streaming |  8 |         0 |
| node-02 | 172.17.210.19 | Leader  | running   |  8 |           |
+---------+---------------+---------+-----------+----+-----------+
```

И в момент сразу после включения выпавшей ноды:
```commandline
Wed Apr 16 15:07:04 UTC 2025

+ Cluster: postgres (7493617658843587548) ------+----+-----------+
| Member  | Host          | Role    | State     | TL | Lag in MB |
+---------+---------------+---------+-----------+----+-----------+
| node-00 | 172.17.210.17 | Replica | stopped   |    |   unknown |
| node-01 | 172.17.210.18 | Replica | streaming |  9 |         0 |
| node-02 | 172.17.210.19 | Leader  | running   |  9 |           |
+---------+---------------+---------+-----------+----+-----------+
Wed Apr 16 15:07:06 UTC 2025

+ Cluster: postgres (7493617658843587548) ------+----+-----------+
| Member  | Host          | Role    | State     | TL | Lag in MB |
+---------+---------------+---------+-----------+----+-----------+
| node-00 | 172.17.210.17 | Replica | running   |  7 |       416 |
| node-01 | 172.17.210.18 | Replica | streaming |  9 |         0 |
| node-02 | 172.17.210.19 | Leader  | running   |  9 |           |
+---------+---------------+---------+-----------+----+-----------+
```

Спустя небольшое время, данные докатываются на восстановившуюся ноду, лаг устраняется
```commandline
Wed Apr 16 15:08:07 UTC 2025

+ Cluster: postgres (7493617658843587548) ------+----+-----------+
| Member  | Host          | Role    | State     | TL | Lag in MB |
+---------+---------------+---------+-----------+----+-----------+
| node-00 | 172.17.210.17 | Replica | streaming |  9 |         0 |
| node-01 | 172.17.210.18 | Replica | streaming |  9 |         0 |
| node-02 | 172.17.210.19 | Leader  | running   |  9 |           |
+---------+---------------+---------+-----------+----+-----------+
```
