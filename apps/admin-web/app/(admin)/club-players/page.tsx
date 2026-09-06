"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function ClubPlayersPage() {
  const [groups, setGroups] = useState<any[]>([]);
  useEffect(() => { api("/api/clubs/my").then(async (data) => {
    const clubs = data.clubs || [];
    const members = await Promise.all(clubs.map(async (club: any) => ({ club, members: (await api(`/api/clubs/${club.id}/members`)).members || [] })));
    setGroups(members);
  }); }, []);
  return <div><h1 className="text-2xl font-bold text-sun-gold-light mb-6">ผู้เล่นในคลับ</h1>{groups.map(({ club, members }) => <div key={club.id} className="card mb-4"><h2 className="text-sun-gold-light font-bold mb-3">{club.name}</h2>{members.map((member: any) => <div key={member.user_id} className="flex justify-between py-2 border-b border-sun-gold/10"><span>{member.display_name || member.username}</span><span>{member.role}</span></div>)}</div>)}</div>;
}
