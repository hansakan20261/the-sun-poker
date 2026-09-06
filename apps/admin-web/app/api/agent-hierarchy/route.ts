import { NextRequest, NextResponse } from "next/server";

const API_BASE = "http://129.212.236.4:3002";

export async function GET(req: NextRequest) {
  const token = req.headers.get("authorization");
  if (!token) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    // Get agent hierarchy data from wallet service
    const res = await fetch(`${API_BASE}/admin/agent-hierarchy`, {
      headers: { Authorization: token },
    });
    const data = await res.json();
    return NextResponse.json(data);
  } catch (err) {
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}
