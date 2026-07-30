begin;

do $$
begin
  if exists (
    select 1
    from public.players
    where id = 'fdb8a5b6-16b1-4f36-7f33-dbff254957c2'::uuid
  ) then
    insert into public.season_rosters (id, season_team_id, season_id, player_id) values
      ('afd75887-d7a9-4c93-a052-b8b577d0b28d'::uuid, 'a0fe31a9-2622-47e3-ba8f-76c44906dd07'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'fdb8a5b6-16b1-4f36-7f33-dbff254957c2'::uuid),
      ('918a932a-3007-44c3-8d09-75d7b558f4f4'::uuid, 'c55c2d46-8bcc-4def-ac46-6c50c0beb609'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '11237ebb-0f46-782f-a61c-49ff277045a8'::uuid),
      ('749b996b-f516-45da-bd07-c7f5d886f412'::uuid, 'f007c3fc-a331-4a5a-ac49-49b137606db2'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'd0779b1a-0526-17e3-e053-7a90456c4479'::uuid),
      ('8be398ef-3a35-48c9-b390-37e61df51a4f'::uuid, '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'b955cca8-26c0-4967-4ecf-bfc4bc6e6abe'::uuid),
      ('f2cb9a9b-bc86-458c-8524-f75a3054fa86'::uuid, 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '3566ceed-11c1-ec05-d3b4-cdbc8bd255ff'::uuid),
      ('d9b86746-bf53-4800-baef-a7d730012cb3'::uuid, '9d23ff79-0791-4c40-a2ff-3c8486779d8d'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, 'c96cdca1-9de2-e7dc-eb6f-0f187298517f'::uuid),
      ('669d600e-0168-4147-81c4-1b16a5b9a2b1'::uuid, '8a76a183-168d-4ac6-90d3-ae143895852b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '5c9ab724-89b2-4844-dc33-b0aa07b7bbb7'::uuid),
      ('bceac77a-aa75-48b5-ac3d-97d16bba604b'::uuid, '8a427ef3-ba9a-402f-9222-abe9caea7e91'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '2d77801d-befd-ec3a-ac18-96e7ef45e116'::uuid),
      ('6de96afd-7128-4484-a123-ca408f7ad00b'::uuid, 'a14994fd-8d5b-40ea-bec1-af21d59fdd9b'::uuid, 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid, '31ad46dd-302e-737d-ffff-92178695fafd'::uuid)
    on conflict (id) do update set
      season_team_id = excluded.season_team_id,
      season_id = excluded.season_id,
      player_id = excluded.player_id;
  end if;
end
$$;

commit;
