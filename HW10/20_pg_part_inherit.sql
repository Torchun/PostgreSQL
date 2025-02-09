-- Создаем сетевую инфраструктуру для VM:
yc vpc network create --name otus-net --description "otus-net" && \
yc vpc subnet create --name otus-subnet --range 192.168.0.0/24 --network-name otus-net --description "otus-subnet" && \
yc compute instance create --name otus-vm --hostname otus-vm --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2004-lts --network-interface subnet-name=otus-subnet,nat-ip-version=ipv4 --ssh-key ~/.ssh/yc_key.pub 

vm_ip_address=$(yc compute instance show --name otus-vm | grep -E ' +address' | tail -n 1 | awk '{print $2}') && ssh -o StrictHostKeyChecking=no -i ~/.ssh/yc_key yc-user@$vm_ip_address 

sudo apt update && sudo apt upgrade -y -q && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo apt -y install postgresql-14 

pg_lsclusters

sudo nano /etc/postgresql/14/main/postgresql.conf
sudo nano /etc/postgresql/14/main/pg_hba.conf

sudo -u postgres psql
alter user postgres password 'postgres';

sudo pg_ctlcluster 14 main restart

wget https://edu.postgrespro.ru/demo_small.zip && sudo apt install unzip && unzip demo_small.zip && sudo -u postgres psql -d postgres -f /home/yc-user/demo_small.sql -c 'alter database demo set search_path to bookings' 

yc compute instances list 

yc compute instance delete otus-vm && yc vpc subnet delete otus-subnet && yc vpc network delete otus-net


drop table if exists table0 cascade;

create table table0 (
	id bigserial primary key,
	name text,
	create_date date,
	some_sum numeric
);

create table table0_2020_03 (like table0 including all) inherits (table0);
alter table table0_2020_03 add check (create_date between date'2020-03-01' and date'2020-04-01' - 1);

create table table0_2020_01 () inherits (table0);
alter table table0_2020_01 add check (create_date between date'2020-01-01' and date'2020-02-01' - 1);

create table table0_2020_02 (check (create_date between date'2020-02-01' and date'2020-03-01' - 1)) inherits (table0);

create or replace function table0_select_part() returns trigger as $$
begin
    if new.create_date between date'2020-01-01' and date'2020-02-01' - 1 then
        insert into table0_2020_01 values (new.*);
    elsif new.create_date between date'2020-02-01' and date'2020-03-01' - 1 then
        insert into table0_2020_02 values (new.*);
	elsif new.create_date between date'2020-03-01' and date'2020-04-01' - 1 then
        insert into table0_2020_03 values (new.*);
    else
        raise exception 'this date not in your partitions. add partition';
    end if;
    return null;
end;
$$ language plpgsql;

create trigger check_date_table0
before insert on table0
for each row execute procedure table0_select_part();

insert into table0 values (1, 'some_text', date'2020-01-02', 100.0);

explain analyze
select * from table0 where id = 1;

select * from table0_2020_01;

explain analyze 
select * from table0 where create_date = '2020-01-02';

explain analyze
insert into table0 values (1, 'some_text', date'2020-03-02', 100.0);
select * from table0_2020_03;

insert into table0 values (1, 'some_text', date'2020-05-02', 100.0); -- Ошибка: this date not in your partitions. add partition

update table0 set create_date = date'2020-02-02' where id = 1; -- Перенос данных путем обновления из секции в секцию не получится

truncate table0;
truncate table0_2020_01;
truncate table0_2020_02;
truncate table0_2020_03;

insert into table0 (id, create_date) select generate_series, date'2020-02-01' from generate_series(1, 10000);

select * from table0_2020_02;
select * from table0;

select pg_size_pretty(pg_table_size('table0')) as main,
       pg_size_pretty(pg_table_size('table0_2020_01')) as january,
       pg_size_pretty(pg_table_size('table0_2020_02')) as february,
       pg_size_pretty(pg_table_size('table0_2020_03')) as march;






