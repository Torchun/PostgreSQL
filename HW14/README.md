# HW 14. Работа с join'ами, статистикой
 - В результате выполнения ДЗ вы научитесь пользоваться различными вариантами соединения таблиц.
 - В данном задании тренируются навыки написания запросов с различными типами соединений.

<hr>

### Подготовка
 - Сделать комментарии на каждый запрос
 - К работе приложить структуру таблиц, для которых выполнялись соединения


Данные из [https://postgrespro.ru/education/demodb](https://postgrespro.ru/education/demodb) - см. [HW10](https://github.com/Torchun/PostgreSQL/blob/main/HW10/README.md)

Схема: [https://postgrespro.ru/docs/postgrespro/10/apjs02](https://postgrespro.ru/docs/postgrespro/10/apjs02) 

 - Реализовать прямое соединение двух или более таблиц
 > Посадочные места бизнес-класса по каждой модели самолёта
```sql
SELECT
  * 
FROM
  aircrafts_data ad 
JOIN 
  seats s 
ON 
  s.aircraft_code = ad.aircraft_code 
WHERE 
  s.fare_conditions = 'Business'
;
```

 - Реализовать левостороннее (или правостороннее) соединение двух или более таблиц
 > Прибывшие рейсы по каждому аэропорту
```sql
SELECT
  ad.airport_name, f.flight_no
FROM 
  airports_data ad
LEFT JOIN 
  flights f
ON
  f.arrival_airport = ad.airport_code 
WHERE
  f.status = 'Arrived'
;
```

 - Реализовать кросс соединение двух или более таблиц
 > Код аэропорта × код самолета, т.е. перемножение двух множеств M×N
```sql
SELECT
  ap.airport_code, ac.aircraft_code
FROM
  airports_data ap
CROSS JOIN
  aircrafts_data ac
;
```

 - Реализовать полное соединение двух или более таблиц
 > Аэропорт "Елизово" (1шт) <+> полёты рейса "PG0648" (61 шт) + аэропорт прибытия "PKC" (26шт)
```sql
SELECT
  ad.airport_code, f.flight_no
FROM
  airports_data ad
FULL JOIN
  flights f
ON
  f.arrival_airport = ad.airport_code
WHERE
  ad.airport_code = 'PKC' OR f.flight_no = 'PG0648'
;
-- 87 записей
```

 - Реализовать запрос, в котором будут использованы разные типы соединений
 > Все билеты, вылетевшие в течении 20.07.2017 GMT+3 во всех аэропортах
```sql
SELECT * FROM airports_data ad 
  LEFT JOIN flights f ON ad.airport_code = f.departure_airport
  JOIN ticket_flights tf ON tf.flight_id = f.flight_id 
  JOIN boarding_passes bp ON bp.ticket_no = tf.ticket_no AND bp.flight_id = f.flight_id 
WHERE  '2017-07-20 00:00:00.000 +0300' < f.actual_departure AND f.actual_departure < '2017-07-20 23:59:59.999 +0300'
;
```
