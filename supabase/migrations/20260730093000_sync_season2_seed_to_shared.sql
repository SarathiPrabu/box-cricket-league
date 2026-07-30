begin;

do $$
begin
  if exists (
    select 1
    from public.leagues
    where id = 'ec653584-c2bf-3060-1bd3-c62ce33c6515'::uuid
  ) then

insert into public.seasons (id, league_id, name, starts_on, ends_on, players_per_team) values
  ('f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'ec653584-c2bf-3060-1bd3-c62ce33c6515'::uuid, 'Season 2', null, null, 9)
on conflict (id) do update set
  league_id = excluded.league_id,
  name = excluded.name,
  starts_on = excluded.starts_on,
  ends_on = excluded.ends_on,
  players_per_team = excluded.players_per_team;

update public.teams
set name = 'Short Pitch Sharks'
where id = '185ca10b-db5a-9620-c7e9-dc8909190db2'::uuid;

update public.legacy_season_player_stats
set source_team_name = 'Short Pitch Sharks'
where source_team_name = 'Short-Pitch Sharks';

update public.players
set display_name = 'Nikhil Jaiswal',
    slug = public.slugify_player_name('Nikhil Jaiswal')
where id = 'd263dd01-ab33-bb85-b203-446097384269'::uuid;

with seed_teams (id, name, slug) as (values
  ('57a492aa-3a6f-4131-8d3a-7601cbcbfd64'::uuid, 'Dhurandhars United', 'dhurandhars-united'),
  ('233702c5-1b72-4306-bc75-568a92f4d514'::uuid, 'Indian Lions', 'indian-lions'),
  ('c787e828-ac30-4e7e-af79-327403aa10b7'::uuid, 'Titans', 'titans')
)
insert into public.teams (id, league_id, name, slug)
select id, 'ec653584-c2bf-3060-1bd3-c62ce33c6515'::uuid, name, slug
from seed_teams
on conflict (id) do update set
  league_id = excluded.league_id,
  name = excluded.name,
  slug = excluded.slug;

with seed_players (id, display_name) as (values
  ('651b236c-f8d8-4dc4-9cf1-2b2160e4182e'::uuid, 'Amit Pandit'),
  ('c3e60feb-63f2-4026-b486-d9b855faa4c6'::uuid, 'Mayank Mishra'),
  ('8b89b16f-d8c7-401a-90ca-3d2705e06995'::uuid, 'Praveen Maddela'),
  ('2ea3dc87-df37-48e7-9ba4-a339784f2248'::uuid, 'Sanjay Patil'),
  ('53436aa5-c6ad-44b0-94eb-64e75bff623c'::uuid, 'Arun Varghese'),
  ('fbc87e96-0e8b-4ca9-8a9c-98f80aa88617'::uuid, 'Ashish Balsaraf'),
  ('3ce66644-6f59-4fd1-80c0-0a1175ec20cb'::uuid, 'Sarathi Mohan'),
  ('31ab3550-0057-4a24-ae55-c7a405b1995b'::uuid, 'Sathishkumar Ramaiyan'),
  ('e611993e-12e9-4e9a-87e3-70ac8abdd67d'::uuid, 'Naveen Amin'),
  ('e1acbc36-22b9-4bb5-bcd4-ea6c672255e4'::uuid, 'Rahul Gupta'),
  ('09cade46-27ed-49ab-a78d-356b3b32a516'::uuid, 'Yug Vajani'),
  ('710f0aa3-ea60-481b-9f76-403dde35df44'::uuid, 'Adarsh Chhajed'),
  ('79e57c4b-6920-4c39-b269-f8a05caffbed'::uuid, 'Amar Hete'),
  ('21d5620d-a499-4c15-9e7e-95b3b90daea5'::uuid, 'Cp Jain'),
  ('ec2c82c6-aa76-4dae-af75-8497cb55ae7f'::uuid, 'Jiteen Shinde'),
  ('69e46096-5c6f-44f3-967e-c02c593a9906'::uuid, 'Raj Kumar'),
  ('117b663a-b615-4b65-82cb-8712e1517afb'::uuid, 'Vicky P')
)
insert into public.players (id, display_name, full_name, created_by)
select id, display_name, null, null
from seed_players
on conflict (id) do update set
  display_name = excluded.display_name,
  full_name = excluded.full_name;

with seed_season_teams (id, season_id, team_id) as (values
  ('a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '57a492aa-3a6f-4131-8d3a-7601cbcbfd64'::uuid),
  ('c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '27c1f2c3-e6c0-44e0-f09c-1961014578df'::uuid),
  ('f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '233702c5-1b72-4306-bc75-568a92f4d514'::uuid),
  ('993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'e9096c6d-7abd-498e-5606-d86773e2efc1'::uuid),
  ('b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'b78a30c1-286b-e8b4-1c1f-ec65b033fcd0'::uuid),
  ('9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '43f275b1-daa6-27a9-e6ce-154211f99d69'::uuid),
  ('8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '72e6d977-5489-abf1-30c8-eda70fa004cc'::uuid),
  ('8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '185ca10b-db5a-9620-c7e9-dc8909190db2'::uuid),
  ('a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'c787e828-ac30-4e7e-af79-327403aa10b7'::uuid)
)
insert into public.season_teams (id, season_id, team_id)
select id, season_id, team_id
from seed_season_teams
on conflict (id) do update set
  season_id = excluded.season_id,
  team_id = excluded.team_id;

with seed_season_rosters (id, season_team_id, season_id, player_id) as (values
  ('0f30356f-b8d0-4000-aa1f-b0bd1e7f85f3'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '8dc0f614-0682-aff5-f0dd-420f37069659'::uuid),
  ('b3b40b29-594b-4dcf-8ad5-7eb7759d8096'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '651b236c-f8d8-4dc4-9cf1-2b2160e4182e'::uuid),
  ('b1aa9b79-3a2c-4a6c-aaeb-31676b260d58'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'c90547ac-af96-598b-5a0e-e06261c553ff'::uuid),
  ('319c1f78-1fe9-4269-9591-00144cf03253'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'c3e60feb-63f2-4026-b486-d9b855faa4c6'::uuid),
  ('973f434e-9769-4d81-a529-22c48db7875d'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '68a1e61a-341f-2061-73dd-74e27d156894'::uuid),
  ('b7819125-953d-4a2b-8aab-0d68ce90a7b4'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '8b89b16f-d8c7-401a-90ca-3d2705e06995'::uuid),
  ('35491da2-852a-4931-bcb3-e98975a34483'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '2ea3dc87-df37-48e7-9ba4-a339784f2248'::uuid),
  ('d7d6c3ff-244b-49ef-aa24-15ff3b9bf66f'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'c9ccf924-eb78-00bc-104f-9ec7bd61903d'::uuid),
  ('afd75887-d7a9-4c93-a052-b8b577d0b28d'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'fdb8a5b6-16b1-4f36-7f33-dbff254957c2'::uuid),
  ('6b294b15-17ae-407a-b561-8109518152b5'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '53436aa5-c6ad-44b0-94eb-64e75bff623c'::uuid),
  ('586fa3fe-7c9b-4f69-84f3-2c26d8549808'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'fbc87e96-0e8b-4ca9-8a9c-98f80aa88617'::uuid),
  ('5f5b9e26-e8a7-4893-8277-1281ebbffb73'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'add689b8-4d9d-ac31-61db-4546be061eb7'::uuid),
  ('84afeb53-6ff7-476f-aae5-99a39a1dd345'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '87f2e792-29cf-7c56-32d1-946291caaa1e'::uuid),
  ('b4dc21c3-85c0-4be7-9a27-692e57749bc6'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '87354cbc-237c-ccee-b1ec-9aa3d7afc7c4'::uuid),
  ('adeb0282-099e-4528-b30e-715c4afcecc1'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'db000b12-d892-4e07-a036-e1bb8aff4829'::uuid),
  ('58aa5a62-6c6a-4481-9572-b86c69931821'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'fc9df8ed-efb1-a256-8083-13275a3b5e50'::uuid),
  ('7f10302e-9862-4659-ace2-0d8d51ea823e'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'f19a0e89-3c24-7dd5-e3a7-c5505b91cc3a'::uuid),
  ('918a932a-3007-44c3-8d09-75d7b558f4f4'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '11237ebb-0f46-782f-a61c-49ff277045a8'::uuid),
  ('b61267c6-7c64-47e9-96d6-3490ea04e87f'::uuid, 'f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '95c057be-c118-1b13-69a2-20b10955e4cb'::uuid),
  ('dcf9b7fd-c8bc-4ec4-af8a-2a920b50112b'::uuid, 'f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '79aac98e-36d5-bdd1-6933-6c78defc724f'::uuid),
  ('8e796f07-7f91-49ff-82e5-cb7a98f2fb36'::uuid, 'f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'd263dd01-ab33-bb85-b203-446097384269'::uuid),
  ('0795d527-3bed-4fe0-9471-27fb276a6b71'::uuid, 'f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '48bd0420-c17a-e2f1-37d6-344055f729ba'::uuid),
  ('97a84e8b-0558-477b-abc8-8d551249b968'::uuid, 'f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '3ce66644-6f59-4fd1-80c0-0a1175ec20cb'::uuid),
  ('2978410a-ad2b-4610-bcff-d0dedafc7d57'::uuid, 'f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '31ab3550-0057-4a24-ae55-c7a405b1995b'::uuid),
  ('0de70777-6655-4b0d-9a94-60694a745e50'::uuid, 'f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '52bd0ac8-9a82-acd1-9188-49297f346c69'::uuid),
  ('749b996b-f516-45da-bd07-c7f5d886f412'::uuid, 'f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'd0779b1a-0526-17e3-e053-7a90456c4479'::uuid),
  ('22e856ca-19b0-4745-ac54-1b1cdae648b9'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'd1d9b80b-d970-5320-6ddf-525db3cbcf56'::uuid),
  ('c240224a-e2bc-4d83-a665-8504fda727d8'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'e611993e-12e9-4e9a-87e3-70ac8abdd67d'::uuid),
  ('e97c8346-37f2-46c6-a4fa-78324a02f8ba'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'faa870eb-9567-cecc-f07f-c7f06f95434a'::uuid),
  ('aefa9e12-a74f-4f55-b3a6-6593ad3c500c'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '04e44d1b-33ee-e873-7a25-b2042089ad31'::uuid),
  ('542e7ceb-1185-4cf5-b3a0-47b34ffb7a67'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '9be0aace-25c9-4044-ac9f-8107b743e234'::uuid),
  ('a65a161e-ed69-48e5-bd1a-3703f992172f'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'a31c9262-b75d-1d6c-d136-71bdd14ee3f2'::uuid),
  ('d1b5f1be-626d-4836-83b2-46155fbb6693'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'd6f96a62-9291-70de-7577-db91ff513bf5'::uuid),
  ('c029d381-4506-4d27-a65d-73951f1b9f78'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '5eb1f88f-455d-64c3-62b5-a28c00004ce0'::uuid),
  ('8be398ef-3a35-48c9-b390-37e61df51a4f'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'b955cca8-26c0-4967-4ecf-bfc4bc6e6abe'::uuid),
  ('87cef888-ae50-4b7c-9f60-092738bda7b5'::uuid, 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'c77b1988-e19a-f6ff-5dcc-50b281c8c689'::uuid),
  ('91bb9139-8472-413c-a740-de4c2515928b'::uuid, 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '1fbb76dd-d0ce-ff88-94ee-4fa8739cfbea'::uuid),
  ('7e52acef-ecfc-40d6-8276-43545acb251b'::uuid, 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'b8fd0ae6-d074-9cc2-b7d3-5cb1af3cf317'::uuid),
  ('f461b86b-af04-41e4-b335-f4fae15ce02d'::uuid, 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '68e36f93-b821-cfb6-6c4f-7f05be83eef7'::uuid),
  ('ad640f00-a5e1-4d8e-88d2-3e5318605240'::uuid, 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'd1531624-e837-9759-e894-4224d6ea5623'::uuid),
  ('ab793b5b-8e54-4273-901c-b0f028959cfc'::uuid, 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '8682a7c9-12f3-69b9-7478-98f4ce307298'::uuid),
  ('23878981-c60f-4451-823e-2e6d46c81677'::uuid, 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '117b663a-b615-4b65-82cb-8712e1517afb'::uuid),
  ('f2cb9a9b-bc86-458c-8524-f75a3054fa86'::uuid, 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '3566ceed-11c1-ec05-d3b4-cdbc8bd255ff'::uuid),
  ('f72a3786-093f-4743-a1d2-f5bbdc8a0627'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'f9bbbbb8-8e05-80f6-e038-57d7423eaefb'::uuid),
  ('48a81ea0-3e5c-49a0-9ef8-df0de6165a4e'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '686887d7-5850-fcd6-1dd2-ce48557580ee'::uuid),
  ('2a1954e5-014e-4b46-902b-4334152cf06d'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '90e2f4da-542c-30bb-a785-9431e5c26f47'::uuid),
  ('fb00ece2-1caf-43d0-b0d3-4fdcbd55aebc'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '37aad006-2f0a-77d5-a3b0-495e345632c8'::uuid),
  ('e5b4ab32-9d71-4bd7-8157-c6c96609d092'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '81fc3d1a-bd68-291c-1b14-0da436e64e65'::uuid),
  ('56989fc5-d4f6-4a0a-b8ae-ce7773643fda'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '52aae18c-471c-7ab7-468b-37645d89c41a'::uuid),
  ('79e4264e-d429-4ecf-8613-a9c54acc3382'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '82565002-85c8-2a5c-01fa-359b6ef665fa'::uuid),
  ('f3ad9aca-dc81-4c61-9c35-e2358f5f9d8f'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'b6c8af2b-c3cc-436e-ade7-b98a1d5299c7'::uuid),
  ('d9b86746-bf53-4800-baef-a7d730012cb3'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'c96cdca1-9de2-e7dc-eb6f-0f187298517f'::uuid),
  ('97f26e5d-53bb-454f-b5aa-a18c8058f9f3'::uuid, '8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'c26bddb7-e9d7-b0ca-7f4f-e8885edc90b4'::uuid),
  ('a16524ba-1ac6-48ae-9011-56bf65af0adf'::uuid, '8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '4bf4f240-f15c-bc84-2533-cf4f9c9d7cee'::uuid),
  ('d1cc97df-f729-4f2e-a02d-a0b564e4991b'::uuid, '8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '728fd06d-d084-b333-98c6-1c0c81450848'::uuid),
  ('07bbdecf-9bbb-420b-b087-b5c380c7b56d'::uuid, '8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '0235b7be-05be-c032-1b07-e68fe46067aa'::uuid),
  ('c86c06d3-3d82-492e-9940-73dcdb248a09'::uuid, '8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'e1acbc36-22b9-4bb5-bcd4-ea6c672255e4'::uuid),
  ('2ce124da-7ec7-4dff-875b-a760570fe299'::uuid, '8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'fe0291ac-5531-0cce-a2b8-4a7c7c932aab'::uuid),
  ('90b781bd-7151-487f-b009-c4f77c8dc31b'::uuid, '8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '09cade46-27ed-49ab-a78d-356b3b32a516'::uuid),
  ('669d600e-0168-4147-81c4-1b16a5b9a2b1'::uuid, '8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '5c9ab724-89b2-4844-dc33-b0aa07b7bbb7'::uuid),
  ('26e65f06-300a-4133-b088-5f82ca701be0'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '710f0aa3-ea60-481b-9f76-403dde35df44'::uuid),
  ('b2f04020-b4ea-4c25-a885-b49fad647cd7'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '79e57c4b-6920-4c39-b269-f8a05caffbed'::uuid),
  ('5807e739-9032-45b1-bf36-59e3def99e70'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '10a7700e-500a-4459-13c9-0ccc18c9f431'::uuid),
  ('92ad098d-4e76-4eb7-9148-d3f2392d353a'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '21d5620d-a499-4c15-9e7e-95b3b90daea5'::uuid),
  ('ad7d7089-6e9a-4fa1-88e6-29dc496851d0'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '75ca707d-5558-9595-bad1-7418148112f4'::uuid),
  ('57aaa874-ece1-4ffa-9160-86c09b728949'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'ec2c82c6-aa76-4dae-af75-8497cb55ae7f'::uuid),
  ('d0cb1c43-e575-4d7c-9e7c-b4186bfa7d3e'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'c318178b-7461-6191-bf68-63565590698b'::uuid),
  ('2039ef96-f8de-4bec-8e71-13b1fcbb0c87'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '9181e0a4-9a6a-2f82-b438-1c95d4072755'::uuid),
  ('bceac77a-aa75-48b5-ac3d-97d16bba604b'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '2d77801d-befd-ec3a-ac18-96e7ef45e116'::uuid),
  ('9b7fefcf-1d0f-4dac-89f9-38f583e55ffc'::uuid, 'a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'b24f4f2f-5b71-0102-775a-2f09f6a33ae5'::uuid),
  ('616f3569-fa6b-4626-894f-48957280d94e'::uuid, 'a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '421af43d-b60f-f96a-a234-ae356a421afe'::uuid),
  ('7342d4a5-1534-4b7d-8d12-69750d362e54'::uuid, 'a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'd6744517-eb40-b3ba-3039-b32d74267704'::uuid),
  ('4726e2fd-df7b-42b9-91e2-935d78855efc'::uuid, 'a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'd53bf5d3-babd-5d0a-b506-fbcb435883f8'::uuid),
  ('7aa09b14-757d-4b17-b803-998794176849'::uuid, 'a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '69e46096-5c6f-44f3-967e-c02c593a9906'::uuid),
  ('9bc14199-4c81-4fc3-b279-94f8714d05c2'::uuid, 'a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '51af5d5c-56c7-725c-6d6f-93f331886fc0'::uuid),
  ('47ec4bba-2968-4e6e-9779-573150838d4a'::uuid, 'a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'd7c3203c-845b-25c7-3b95-8c4a002b4dfd'::uuid),
  ('6de96afd-7128-4484-a123-ca408f7ad00b'::uuid, 'a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '31ad46dd-302e-737d-ffff-92178695fafd'::uuid)
)
insert into public.season_rosters (id, season_team_id, season_id, player_id)
select id, season_team_id, season_id, player_id
from seed_season_rosters
on conflict (id) do update set
  season_team_id = excluded.season_team_id,
  season_id = excluded.season_id,
  player_id = excluded.player_id;

with seed_season_team_managers (id, season_team_id, player_id, display_name) as (values
  ('255007b3-fc75-4f53-91a9-57796c214dfe'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'fdb8a5b6-16b1-4f36-7f33-dbff254957c2'::uuid, 'Shubham Pandey'),
  ('7cbc9647-e9b7-4300-b84a-0c082e030979'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, '11237ebb-0f46-782f-a61c-49ff277045a8'::uuid, 'Saravanan Veluchamy'),
  ('b4527f93-4c4d-43f8-94d7-e78b7b0cbf2d'::uuid, 'f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'd0779b1a-0526-17e3-e053-7a90456c4479'::uuid, 'Mahendra Baroniya'),
  ('7364f7fd-7c34-4159-8e94-b4c995cd86f6'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'b955cca8-26c0-4967-4ecf-bfc4bc6e6abe'::uuid, 'Swapnil Shah'),
  ('a876efb9-6bd2-4738-927e-0c638ce6d9c9'::uuid, 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, '3566ceed-11c1-ec05-d3b4-cdbc8bd255ff'::uuid, 'Princely Gomes'),
  ('d93af8cd-3743-4bd6-a6bb-f6f285cf1b00'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'c96cdca1-9de2-e7dc-eb6f-0f187298517f'::uuid, 'Mahesh Kshatriya'),
  ('806a0ac4-45a4-477d-b329-ee7b8bfaec00'::uuid, '8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, '5c9ab724-89b2-4844-dc33-b0aa07b7bbb7'::uuid, 'Shreenath Kini'),
  ('14295a3a-895f-4c5f-ba7f-d6ddad9ac2fb'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, '2d77801d-befd-ec3a-ac18-96e7ef45e116'::uuid, 'Supreeth Premkumar'),
  ('9d16cd94-7740-4375-9b0d-021231ce8921'::uuid, 'a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, '31ad46dd-302e-737d-ffff-92178695fafd'::uuid, 'Manish Doijode')
)
insert into public.season_team_managers (id, season_team_id, player_id, user_id, display_name)
select id, season_team_id, player_id, null, display_name
from seed_season_team_managers
on conflict (id) do update set
  season_team_id = excluded.season_team_id,
  player_id = excluded.player_id,
  display_name = excluded.display_name;

  end if;
end
$$;

commit;
