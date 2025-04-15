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

### ETCD

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

