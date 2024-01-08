
-- CS4400: Introduction to Database Systems: Tuesday, September 12, 2023
-- Simple Airline Management System Course Project Mechanics [TEMPLATE] (v0)
-- Views, Functions & Stored Procedures

/* This is a standard preamble for most of our scripts.  The intent is to establish
a consistent environment for the database behavior. */
set global transaction isolation level serializable;
set global SQL_MODE = 'ANSI,TRADITIONAL';
set names utf8mb4;
set SQL_SAFE_UPDATES = 0;

set @thisDatabase = 'flight_tracking';
use flight_tracking;


-- -----------------------------------------------------------------------------
-- phase 3 additional views and tables.
-- -----------------------------------------------------------------------------

create or replace view v_flight_progress_current_leg as
select f.flightID, f.routeID, f.progress, rp.legID, rp.sequence
from flight as f
left join route_path as rp
on f.routeID = rp.routeID and f.progress = rp.sequence;

-- select * from v_flight_progress_current_leg;

create or replace view v_flight_progress as
select f.flightID, f.routeID, f.support_airline, f.support_tail, f.progress, airplane_status, num_legs
from flight as f
left join (select routeID, count(sequence) as num_legs from route_path group by routeID) as t1
on f.routeID = t1.routeID;

-- select * from v_flight_progress;


create or replace view v_flight_airplane_type as
select flightID, support_airline, support_tail, plane_type
from flight as f
left join airplane as a
on f.support_airline = a.airlineID and f.support_tail = a.tail_num;

-- select * from v_flight_airplane_type;

create or replace view v_flight_air as
select t1.departure, t1.arrival, t1.flightID, t1.next_time, a.locationID
from
(select l.departure, l.arrival, fl.flightID, fl.next_time, fl.support_airline, fl.support_tail
from
(select flightID, airplane_status, next_time, legID, support_airline, support_tail
from flight as f
left join route_path as rp
on f.routeID = rp.routeID and f.progress = rp.sequence
where airplane_status = 'in_flight') as fl
left join leg as l
on fl.legID = l.legID) as t1
left join airplane as a
on t1.support_airline = a.airlineID and t1.support_tail = a.tail_num;

-- select * from v_flight_air;

create or replace view v_flight_ground as
select t1.next_departure, t1.flightID, t1.next_time, a.locationID
from
(select l.arrival as next_departure, fl.flightID, fl.next_time, fl.support_airline, fl.support_tail
from
(select flightID, airplane_status, next_time, legID, support_airline, support_tail
from flight as f
left join route_path as rp
on f.routeID = rp.routeID and f.progress = rp.sequence
where airplane_status = 'on_ground' and progress != 0) as fl
left join leg as l
on fl.legID = l.legID
union
select l.departure as next_departure, fl.flightID, fl.next_time, fl.support_airline, fl.support_tail
from
(select flightID, f.routeID, airplane_status, next_time, support_airline, support_tail, rp.legID
from flight as f
left join route_path as rp
on f.routeID = rp.routeID
where f.airplane_status = 'on_ground' and f.progress = 0 and rp.sequence = 1) as fl
left join leg as l
on fl.legID = l.legID) as t1
left join airplane as a
on t1.support_airline = a.airlineID and t1.support_tail = a.tail_num;

-- select * from v_flight_ground;

create or replace view v_people_role as
select
  personID,
  CASE WHEN personID in (select personID from passenger) THEN 1 ELSE 0 END AS passenger,
  CASE WHEN personID in (select personID from pilot) THEN 1 ELSE 0 END AS pilot
from person;

-- select * from v_people_role;

create or replace view v_people_air as
select t2.personID, locationID, departure, arrival, flightID, next_time, passenger, pilot
from
(select p.personID, p.locationID, departure, arrival, flightID, next_time
from person as p
join v_flight_air as t1
on p.locationID = t1.locationID
where p.locationID like 'plane_%') as t2
left join v_people_role as t3
on t2.personID = t3.personID;

-- select * from v_people_air;

create or replace view v_people_ground as
select t2.personID, locationID, airportID, airport_name, city, state, country, passenger, pilot
from
(select p.personID, p.locationID, airportID, airport_name, city, state, country
from person as p
left join airport as a
on p.locationID = a.locationID
where p.locationID like 'port_%') as t2
left join v_people_role as t3
on t2.personID = t3.personID;

-- select * from v_people_ground;

create or replace view v_route_info as
select routeID, rp.legID, sequence, distance, departure, arrival, concat(departure, '->', arrival) as concat_leg
from route_path as rp
left join leg as l
on rp.legID = l.legID;

-- select * from v_route_info;


-- -----------------------------------------------------------------------------
-- stored procedures and views
-- -----------------------------------------------------------------------------
/* Standard Procedure: If one or more of the necessary conditions for a procedure to
be executed is false, then simply have the procedure halt execution without changing
the database state. Do NOT display any error messages, etc. */

-- [_] supporting functions, views and stored procedures
-- -----------------------------------------------------------------------------
/* Helpful library capabilities to simplify the implementation of the required
views and procedures. */
-- -----------------------------------------------------------------------------
drop function if exists leg_time;
delimiter //
create function leg_time (ip_distance integer, ip_speed integer)
	returns time reads sql data
begin
	declare total_time decimal(10,2);
    declare hours, minutes integer default 0;
    set total_time = ip_distance / ip_speed;
    set hours = truncate(total_time, 0);
    set minutes = truncate((total_time - hours) * 60, 0);
    return maketime(hours, minutes, 0);
end //
delimiter ;

-- [1] add_airplane()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new airplane.  A new airplane must be sponsored
by an existing airline, and must have a unique tail number for that airline.
username.  An airplane must also have a non-zero seat capacity and speed. An airplane
might also have other factors depending on it's type, like skids or some number
of engines.  Finally, an airplane must have a new and database-wide unique location
since it will be used to carry passengers. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_airplane;
delimiter //
create procedure add_airplane (in ip_airlineID varchar(50), in ip_tail_num varchar(50),
	in ip_seat_capacity integer, in ip_speed integer, in ip_locationID varchar(50),
    in ip_plane_type varchar(100), in ip_skids boolean, in ip_propellers integer,
    in ip_jet_engines integer)
sp_main: begin
if (select count(*) from airplane where tail_num = ip_tail_num) > 0
	then leave sp_main; end if;
if (ip_seat_capacity <= 0 or ip_speed <= 0)
	then leave sp_main; end if;
if (select count(*) from airplane where locationID = ip_locationID) > 0
	then leave sp_main; end if;

if (select count(*) from airline where airlineID = ip_airlineID) = 0
then
INSERT INTO airline VALUES
(
        ip_airlineID, 0
);
end if;

INSERT INTO location VALUES
(
        ip_locationID
);
    
INSERT INTO airplane VALUES
(
        ip_airlineID,
        ip_tail_num,
        ip_seat_capacity,
        ip_speed,
        ip_locationID,
        ip_plane_type,
        ip_skids,
        ip_propellers,
        ip_jet_engines
    );
end //
delimiter ;

-- [2] add_airport()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new airport.  A new airport must have a unique
identifier along with a new and database-wide unique location if it will be used
to support airplane takeoffs and landings.  An airport may have a longer, more
descriptive name.  An airport must also have a city, state, and country designation. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_airport;
delimiter //
create procedure add_airport (in ip_airportID char(3), in ip_airport_name varchar(200),
    in ip_city varchar(100), in ip_state varchar(100), in ip_country char(3), in ip_locationID varchar(50))
sp_main: begin
if (select count(*) from airport where airportID = ip_airportID) > 0
	then leave sp_main; end if;

if (select count(*) from airport where locationID = ip_locationID) > 0
	then leave sp_main; end if;
    
INSERT INTO location VALUES
(
        ip_locationID
);
    
INSERT INTO airport VALUES
(
        ip_airportID,
        ip_airport_name,
        ip_city,
        ip_state,
        ip_country,
        ip_locationID
    );
end //
delimiter ;

-- [3] add_person()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new person.  A new person must reference a unique
identifier along with a database-wide unique location used to determine where the
person is currently located: either at an airport, or on an airplane, at any given
time.  A person must have a first name, and might also have a last name.

A person can hold a pilot role or a passenger role (exclusively).  As a pilot,
a person must have a tax identifier to receive pay, and an experience level.  As a
passenger, a person will have some amount of frequent flyer miles, along with a
certain amount of funds needed to purchase tickets for flights. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_person;
delimiter //
create procedure add_person (in ip_personID varchar(50), in ip_first_name varchar(100),
    in ip_last_name varchar(100), in ip_locationID varchar(50), in ip_taxID varchar(50),
    in ip_experience integer, in ip_miles integer, in ip_funds integer)
sp_main: begin
if (select count(*) from person where personID = ip_personID) > 0
	then leave sp_main; end if;
if (select count(*) from person where locationID = ip_locationID) > 0
	then leave sp_main; end if;
  
if (ip_experience = 0) 
then
if (select count(*) from location where locationID = ip_locationID) = 0
then
INSERT INTO location VALUES
(
        ip_locationID
);
end if;
    INSERT INTO person VALUES
(
        ip_personID,
        ip_first_name,
        ip_last_name,
        ip_locationID
    );

    INSERT INTO passenger VALUES
(
        ip_personID,
        ip_miles,
        ip_funds
    ); 
    end if;

if (ip_experience <> 0) 
then
if (select count(*) from location where locationID = ip_locationID) = 0
then
INSERT INTO location VALUES
(
        ip_locationID
);
end if;
    
    INSERT INTO person VALUES
(
        ip_personID,
        ip_first_name,
        ip_last_name,
        ip_locationID
    );

    INSERT INTO pilot VALUES
(
        ip_personID,
        ip_taxID,
        ip_experience,
        NULL
    ); 
    end if;
    
end //
delimiter ;

-- [4] grant_or_revoke_pilot_license()
-- -----------------------------------------------------------------------------
/* This stored procedure inverts the status of a pilot license.  If the license
doesn't exist, it must be created; and, if it laready exists, then it must be removed. */
-- -----------------------------------------------------------------------------
drop procedure if exists grant_or_revoke_pilot_license;
delimiter //
create procedure grant_or_revoke_pilot_license (in ip_personID varchar(50), in ip_license varchar(100))
sp_main: begin

if (select count(*) from pilot_licenses where personID = ip_personID and license = ip_license) = 0
then 
INSERT INTO pilot_licenses VALUES
(
        ip_personID,
        ip_license
); 
else 
delete from pilot_licenses where personID = ip_personID;
end if;

end //
delimiter ;
-- [5] offer_flight()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new flight.  The flight can be defined before
an airplane has been assigned for support, but it must have a valid route.  And
the airplane, if designated, must not be in use by another flight.  The flight
can be started at any valid location along the route except for the final stop,
and it will begin on the ground.  You must also include when the flight will
takeoff along with its cost. */
-- -----------------------------------------------------------------------------
drop procedure if exists offer_flight;
delimiter //
create procedure offer_flight (in ip_flightID varchar(50), in ip_routeID varchar(50),
    in ip_support_airline varchar(50), in ip_support_tail varchar(50), in ip_progress integer,
    in ip_next_time time, in ip_cost integer)
sp_main: begin
    if (not exists (select routeID from route where routeID = ip_routeID)) then
        leave sp_main; end if;
    if exists (select support_airline, support_tail from flight 
where support_airline = ip_support_airline and support_tail = ip_support_tail) then
        leave sp_main; end if;
    if exists(select progress from flight where flightID = ip_flightID)  then
        leave sp_main; end if;
    INSERT INTO flight VALUES (ip_flightID, ip_routeID,
    ip_support_airline,ip_support_tail,ip_progress,
    ip_next_time,ip_cost);
end //

delimiter ;



-- [6] flight_landing()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for a flight landing at the next airport
along it's route.  The time for the flight should be moved one hour into the future
to allow for the flight to be checked, refueled, restocked, etc. for the next leg
of travel.  Also, the pilots of the flight should receive increased experience, and
the passengers should have their frequent flyer miles updated. */
-- -----------------------------------------------------------------------------
drop procedure if exists flight_landing;
delimiter //
create procedure flight_landing (in ip_flightID varchar(50))
sp_main: begin
    declare v_new_time time;
    declare v_experience_increase int;
    declare v_frequent_flyer_miles_increase int;
    select next_time into v_new_time from flight where ip_flightID = flight_ID;
    set v_new_time = addtime(v_new_time, '01:00:00');
    update flight set next_time = v_new_time where ip_flightID = flight_ID;
    set v_experience_increase = (select distance from leg where personID = locationID);
    update pilot set experience = experience + v_experience_increase where commanding_flight = ip_flight_ID;
    set v_frequent_flyer_miles_increase = (select distance
from v_flight_progress as t
left join leg as l
on t.legID = l.legID
where flightID = ip_flightID
);
    update passenger set miles = miles + v_frequent_flyer_miles_increase where personID in (select personID from v_people_air where flightID = ip_flightID);

end //
delimiter ;


-- [7] flight_takeoff()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for a flight taking off from its current
airport towards the next airport along it's route.  The time for the next leg of
the flight must be calculated based on the distance and the speed of the airplane.
And we must also ensure that propeller driven planes have at least one pilot
assigned, while jets must have a minimum of two pilots. If the flight cannot take
off because of a pilot shortage, then the flight must be delayed for 30 minutes. */
-- -----------------------------------------------------------------------------
drop procedure if exists flight_takeoff;
delimiter //
create procedure flight_takeoff (in ip_flightID varchar(50))
sp_main: begin
    -- Declare variables for distance, speed, pilots, and time
    declare v_distance int;
    declare v_speed int;
    declare v_required_pilots int;
    declare v_available_pilots int;
    declare v_delay_time time;
    declare v_time_for_next_leg time;
    select distance, speed into v_distance, v_speed from airplane, leg where flight_ID = ip_flightID;
    set v_time_for_next_leg = addtime(current_time(), distance/speed);
    select case
        when plane_type = 'prop' then 1
        when plane_type = 'jet' then 2
        else 0 
    end into v_required_pilots
    from airplane
    where commanding_flight = ip_flightID;
    select count(*) into v_available_pilots from pilot where commanding_flight = ip_flight_ID;
    if v_available_pilots >= v_required_pilots then
        update flight set next_time = v_time_for_next_leg where commanding_flight = ip_flight_ID;
    else
        set v_delay_time = addtime(current_time(), '00:30:00');
        update flight set next_time = v_delay_time where commanding_flight = ip_flight_ID;
    end if;
end //

delimiter ;

-- [8] passengers_board()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for passengers getting on a flight at
its current airport.  The passengers must be at the same airport as the flight,
and the flight must be heading towards that passenger's desired destination.
Also, each passenger must have enough funds to cover the flight.  Finally, there
must be enough seats to accommodate all boarding passengers. */
-- -----------------------------------------------------------------------------
drop procedure if exists passengers_board;
delimiter //
create procedure passengers_board (in ip_flightID varchar(50))
sp_main: begin
    -- Declare variables
    declare v_flight_destination varchar(50);
    declare v_passenger_count int;
    declare v_seats_available int;
    select arrival into v_flight_destination from leg where arrival = v_flight_destination;
    select count(*) into v_passenger_count from passenger where flight_ID = ip_flight_ID;
    select seat_capacity into v_seats_available from airplane where flight_ID = ip_flight_ID;
end //

delimiter ;

-- [9] passengers_disembark()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for passengers getting off of a flight
at its current airport.  The passengers must be on that flight, and the flight must
be located at the destination airport as referenced by the ticket. */
-- -----------------------------------------------------------------------------

drop procedure if exists passengers_disembark;
delimiter //
create procedure passengers_disembark (in ip_flightID varchar(50))
sp_main: begin
	declare airport_location varchar(50);
    select locationID into airport_location from airport where airportID = (select distinct arrival from v_flight_air where flightID = 'dl_10');
    
    -- create a table.
    create table t_passenger_flight_destinations as
	select t3.personID, t3.flightID, t3.arrival, t3.destinations, t4.locationID
	from (select t1.personID, t1.flightID, t1.arrival, t2.destinations
	from v_people_air as t1
	left join
	(select personID, GROUP_CONCAT(airportID SEPARATOR ',') as destinations
	from passenger_vacations
	group by personID) as t2
	on t1.personID = t2.personID
	where flightID = ip_flightID and t1.personID in (select personID from passenger)) as t3
	left join airport as t4
	on t3.arrival = t4.airportID;
    
    -- update location.
    update person
	set locationID = airport_location
	where personID in (select personID
		from t_passenger_flight_destinations
		where FIND_IN_SET(arrival, destinations) > 0);
        
	-- delete table.
    drop table if exists t_passenger_flight_destinations;
end //
delimiter ;


-- call passengers_disembark('dl_10');



-- [10] assign_pilot()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a pilot as part of the flight crew for a given
flight.  The pilot being assigned must have a license for that type of airplane,
and must be at the same location as the flight.  Also, a pilot can only support
one flight (i.e. one airplane) at a time.  The pilot must be assigned to the flight
and have their location updated for the appropriate airplane. */
-- -----------------------------------------------------------------------------

drop procedure if exists assign_pilot;
delimiter //
create procedure assign_pilot (in ip_flightID varchar(50), ip_personID varchar(50))
sp_main: begin
	-- is a pilot
    if ip_personID not in (select personID from pilot)
		then leave sp_main; end if;
        
    -- not already assigned to a flight.
    if ip_personID not in (select personID from pilot where commanding_flight is null)
		then leave sp_main; end if;
        
	-- pilot is at the same location as the flight.
    set @flight_locationID = (select locationID from airport  -- locationID is 'port_12'
		where airportID = (select next_departure from v_flight_ground where flightID = ip_flightID));
        
	set @person_locationID = (select locationID from person where personID = ip_personID);
    
    if @flight_locationID != @person_locationID
		then leave sp_main; end if;
    
    -- pilot being assigned must have a license for that type of airplane
    set @flight_airplane_type = (select plane_type from v_flight_airplane_type where flightID = ip_flightID);
    
    if @flight_airplane_type is not null
		and (@flight_airplane_type not in (select license from pilot_licenses where personID = ip_personID))
		then leave sp_main; end if;
    
    -- Input is valid. assign pilot to flight.
    -- update commanding_flight in pilot table.
    -- update locationID in person table.
    update pilot
	set commanding_flight = ip_flightID
	where personID = ip_personID;
    
    update person
	set locationID = (select locationID from v_flight_ground where flightID = ip_flightID)
	where personID = ip_personID;

end //
delimiter ;


-- [11] recycle_crew()
-- -----------------------------------------------------------------------------
/* This stored procedure releases the assignments for a given flight crew.  The
flight must have ended, and all passengers must have disembarked. */
-- -----------------------------------------------------------------------------

drop procedure if exists recycle_crew;
delimiter //
create procedure recycle_crew (in ip_flightID varchar(50))
sp_main: begin
	-- no passenger on the flight.
    if (select count(passenger) from v_people_air where flightID = ip_flightID) != 0
		then leave sp_main; end if;
        
	-- flight has ended. status is on_ground.
    if (select airplane_status from v_flight_progress where flightID = ip_flightID) != 'on_ground'
		then leave sp_main; end if;
        
	-- flight has ended. progress = num_legs.
    if (select progress from v_flight_progress where flightID = ip_flightID) != 
		(select num_legs from v_flight_progress where flightID = ip_flightID)
		then leave sp_main; end if;
        
	-- Input is valid. recycle crew.
    -- update commanding_flight in pilot table to null.
    -- update locationID in person table to airport locationID.
    set @current_airportID = (select arrival -- get current location as airportID
							from v_flight_progress_current_leg as t1
							left join leg as l
							on t1.legID = l.legID
							where flightID = 'am_99');
                            
	update person
	set locationID = (select locationID from airport where airportID = @current_airportID)
	where personID in (select personID from pilot where commanding_flight = ip_flightID);
    
    update pilot
	set commanding_flight = null
	where commanding_flight = ip_flightID;    
    
end //
delimiter ;

-- [12] retire_flight()
-- -----------------------------------------------------------------------------
/* This stored procedure removes a flight that has ended from the system.  The
flight must be on the ground, and either be at the start its route, or at the
end of its route.  And the flight must be empty - no pilots or passengers. */
-- -----------------------------------------------------------------------------

drop procedure if exists retire_flight;
delimiter //
create procedure retire_flight (in ip_flightID varchar(50))
sp_main: begin
	-- no passenger on the flight.
    if (select count(passenger) from v_people_air where flightID = ip_flightID) != 0
		then leave sp_main; end if;
        
	-- no pilot on the flight.
    if (select count(pilot) from v_people_air where flightID = ip_flightID) != 0
		then leave sp_main; end if;
        
	-- flight has ended. status is on_ground.
    if (select airplane_status from v_flight_progress where flightID = ip_flightID) != 'on_ground'
		then leave sp_main; end if;
        
	-- flight has ended. progress = num_legs or progress = 0.
    set @progress = (select progress from v_flight_progress where flightID = ip_flightID);
    set @num_legs = (select num_legs from v_flight_progress where flightID = ip_flightID);
    
    if @progress not in (0, @num_legs)
		then leave sp_main; end if;

	-- Input is valid. retire flight. remove flightID from flight table.
    delete from flight where flightID = ip_flightID;

end //
delimiter ;



-- [13] simulation_cycle()
-- -----------------------------------------------------------------------------
/* This stored procedure executes the next step in the simulation cycle.  The flight
with the smallest next time in chronological order must be identified and selected.
If multiple flights have the same time, then flights that are landing should be
preferred over flights that are taking off.  Similarly, flights with the lowest
identifier in alphabetical order should also be preferred.

If an airplane is in flight and waiting to land, then the flight should be allowed
to land, passengers allowed to disembark, and the time advanced by one hour until
the next takeoff to allow for preparations.

If an airplane is on the ground and waiting to takeoff, then the passengers should
be allowed to board, and the time should be advanced to represent when the airplane
will land at its next location based on the leg distance and airplane speed.

If an airplane is on the ground and has reached the end of its route, then the
flight crew should be recycled to allow rest, and the flight itself should be
retired from the system. */
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS simulation_cycle;
DELIMITER //

CREATE PROCEDURE simulation_cycle()
BEGIN
    DECLARE selectedFlightID VARCHAR(50);


    SELECT flightID INTO selectedFlightID
    FROM flight
    ORDER BY next_time, airplane_status = 'on_ground', flightID
    LIMIT 1;


    IF EXISTS (SELECT 1 FROM flight WHERE airplane_status = 'in_flight' AND flightID = selectedFlightID) THEN
        CALL flight_landing(selectedFlightID);
        CALL passengers_disembark(selectedFlightID); 
    END IF;
    

    IF EXISTS (SELECT 1 FROM flight WHERE airplane_status = 'on_ground' AND flightID = selectedFlightID) THEN
        CALL passengers_board(selectedFlightID);
        CALL flight_takeoff(selectedFlightID);
    END IF;

    IF EXISTS (
        SELECT 1 FROM flight f
        JOIN route_path rp ON f.routeID = rp.routeID
        WHERE f.airplane_status = 'on_ground' 
        AND f.flightID = selectedFlightID
        AND f.progress = rp.sequence
    ) THEN 
        CALL recycle_crew(selectedFlightID);
        CALL retire_flight(selectedFlightID);
    END IF;
END //

DELIMITER ;




-- [14] flights_in_the_air()
-- -----------------------------------------------------------------------------
/* This view describes where flights that are currently airborne are located. */
-- -----------------------------------------------------------------------------
CREATE OR REPLACE view flights_in_the_air as (
SELECT 
l.departure, 
l.arrival, 
COUNT(k.flightID), 
GROUP_CONCAT(k.flightID), 
MIN(k.next_time), 
MAX(k.next_time),  
GROUP_CONCAT(locationID)

FROM flight_tracking.leg l
LEFT OUTER JOIN
(SELECT flightID, routeID AS flight_routeID, support_airline, support_tail, progress, airplane_status, next_time, locationID, rp.legID FROM flight_tracking.flight f
LEFT OUTER JOIN
flight_tracking.airplane a
ON
f.support_airline = a.airlineID
AND
f.support_tail = a.tail_num
LEFT OUTER JOIN 
(SELECT routeID AS rp_routeID, legID, sequence FROM flight_tracking.route_path) rp
ON rp.rp_routeID = f.routeID
AND sequence = f.progress
) k
ON
l.legID = k.legID

WHERE k.airplane_status = 'in_flight'

GROUP BY 
l.departure,
l.arrival
);

-- [15] flights_on_the_ground()
-- -----------------------------------------------------------------------------
/* This view describes where flights that are currently on the ground are located. */
-- -----------------------------------------------------------------------------
create or replace view flights_on_the_ground (departing_from, num_flights,
	flight_list, earliest_arrival, latest_arrival, airplane_list) as 
select next_departure, count(*), GROUP_CONCAT(flightID SEPARATOR ','), min(next_time), max(next_time), GROUP_CONCAT(locationID SEPARATOR ',')
from
(select t1.next_departure, t1.flightID, t1.next_time, a.locationID
from
(select l.arrival as next_departure, fl.flightID, fl.next_time, fl.support_airline, fl.support_tail
from
(select flightID, airplane_status, next_time, legID, support_airline, support_tail
from flight as f
left join route_path as rp
on f.routeID = rp.routeID and f.progress = rp.sequence
where airplane_status = 'on_ground' and progress != 0) as fl
left join leg as l
on fl.legID = l.legID
union
select l.departure as next_departure, fl.flightID, fl.next_time, fl.support_airline, fl.support_tail
from
(select flightID, f.routeID, airplane_status, next_time, support_airline, support_tail, rp.legID
from flight as f
left join route_path as rp
on f.routeID = rp.routeID
where f.airplane_status = 'on_ground' and f.progress = 0 and rp.sequence = 1) as fl
left join leg as l
on fl.legID = l.legID) as t1
left join airplane as a
on t1.support_airline = a.airlineID and t1.support_tail = a.tail_num) as t2
group by next_departure;

-- [16] people_in_the_air()
-- -----------------------------------------------------------------------------
/* This view describes where people who are currently airborne are located. */
-- -----------------------------------------------------------------------------
create or replace view people_in_the_air (departing_from, arriving_at, num_airplanes,
	airplane_list, flight_list, earliest_arrival, latest_arrival, num_pilots,
	num_passengers, joint_pilots_passengers, person_list) as
SELECT
o.departure,
o.arrival,
COUNT(DISTINCT locationID) AS num_airplanes,
GROUP_CONCAT(DISTINCT a.locationID) AS airplane_list,
GROUP_CONCAT(DISTINCT f.flightID) AS flight_list,
MIN(f.next_time) AS earliest_arrival,
MAX(f.next_time) AS latest_arrival,
SUM(!ISNULL(p.taxID)) AS pilots,
SUM(!ISNULL(p.miles)) as passengers,
COUNT(*) as joint_pilots_passengers,
GROUP_CONCAT(p.perID) as person_list

FROM flight_tracking.flight f
LEFT OUTER JOIN
flight_tracking.airplane a
ON
airlineID = support_airline
AND
tail_num = support_tail
LEFT OUTER JOIN 
(SELECT per.personID as perID, locationID AS locID, taxID, miles, locationID as person_locationID 
FROM flight_tracking.person per
LEFT OUTER JOIN
flight_tracking.pilot pil
ON
per.personID = pil.personID
LEFT OUTER JOIN
flight_tracking.passenger pass
ON
per.personID = pass.personID
) p
ON locationID = locID
LEFT OUTER JOIN
(SELECT routeID, l.legID AS route_legID, sequence, departure, arrival FROM flight_tracking.route_path rp
LEFT OUTER JOIN
flight_tracking.leg l
ON
rp.legID = l.legID) o
ON o.routeID = f.routeID
AND
f.routeID = o.routeID
AND
f.progress = o.sequence
WHERE airplane_status = 'in_flight'

GROUP BY
o.departure,
o.arrival;

-- [17] people_on_the_ground()
-- -----------------------------------------------------------------------------
/* This view describes where people who are currently on the ground are located. */
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW people_on_the_ground AS (
SELECT 
ap.airportID AS departing_from,
ap.locationID AS airport,
ap.airport_name,
ap.city,
ap.state,
ap.country,
SUM(!ISNULL(p.taxID)) AS pilots,
SUM(!ISNULL(p.miles)) as passengers,
SUM(!ISNULL(p.taxID)) + SUM(!ISNULL(p.miles)) as joint_pilots_passengers,
GROUP_CONCAT(p.perID) as person_list
FROM
flight_tracking.airport ap
LEFT OUTER JOIN
(SELECT per.personID as perID, locationID AS locID, taxID, miles, locationID as person_locationID 
FROM flight_tracking.person per
LEFT OUTER JOIN
flight_tracking.pilot pil
ON
per.personID = pil.personID
LEFT OUTER JOIN
flight_tracking.passenger pass
ON
per.personID = pass.personID
) p
ON p.locID = ap.locationID

WHERE ap.locationID LIKE 'port%'

GROUP BY
airportID,
locationID,
airport_name,
city,
state,
country

HAVING
(SUM(!ISNULL(p.taxID))) > 0 OR (SUM(!ISNULL(p.miles)) > 0));



-- [18] route_summary()
-- -----------------------------------------------------------------------------
/* This view describes how the routes are being utilized by different flights. */
-- -----------------------------------------------------------------------------
create or replace view route_summary (route, num_legs, leg_sequence, route_length,
	num_flights, flight_list, airport_sequence) as
select t1.routeID, num_legs, leg_sequence, route_length,
	coalesce(t2.num_flights, 0) as num_flights, flight_list, airport_sequence
from
(select routeID, count(*) as num_legs, GROUP_CONCAT(legID SEPARATOR ',') as leg_sequence, sum(distance) as route_length,
	GROUP_CONCAT(concat_leg ORDER BY sequence SEPARATOR ',') as airport_sequence
from v_route_info
group by routeID) as t1
left join
(select routeID, count(*) as num_flights, GROUP_CONCAT(flightID SEPARATOR ',') as flight_list
from flight
group by routeID) as t2
on t1.routeID = t2.routeID;


-- [19] alternative_airports()
-- -----------------------------------------------------------------------------
/* This view displays airports that share the same city and state. */
-- -----------------------------------------------------------------------------
create or replace view alternative_airports (city, state, country, num_airports,
	airport_code_list, airport_name_list) as
select city, state, country, count(*) as num_airport, GROUP_CONCAT(airportID SEPARATOR ','), GROUP_CONCAT(airport_name SEPARATOR ',')
from airport
group by city, state, country
having num_airport > 1;