import { NextResponse } from "next/server";
import { destroySession } from "@/lib/auth";

export async function POST(request: Request) {
  await destroySession();
  const { origin } = new URL(request.url);
  return NextResponse.redirect(origin, { status: 302 });
}
