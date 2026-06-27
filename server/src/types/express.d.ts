export {};

// Augment Express Request with the authenticated 'actor' context.
// Using module augmentation on express-serve-static-core is the most reliable
// way to extend the Request type when files import { Request } from "express".
declare module "express-serve-static-core" {
  interface Request {
    actor: {
      type: "board" | "agent" | "none";
      userId?: string;
      userName?: string | null;
      userEmail?: string | null;
      agentId?: string;
      companyId?: string;
      companyIds?: string[];
      memberships?: Array<{
        companyId: string;
        membershipRole?: string | null;
        status?: string;
      }>;
      isInstanceAdmin?: boolean;
      keyId?: string;
      runId?: string;
      source?: "local_implicit" | "session" | "board_key" | "agent_key" | "agent_jwt" | "cloud_tenant" | "none";
    };
  }
}

// Also augment the global Express namespace for any code that uses the Express. namespace style.
declare global {
  namespace Express {
    interface Request {
      actor: {
        type: "board" | "agent" | "none";
        userId?: string;
        userName?: string | null;
        userEmail?: string | null;
        agentId?: string;
        companyId?: string;
        companyIds?: string[];
        memberships?: Array<{
          companyId: string;
          membershipRole?: string | null;
          status?: string;
        }>;
        isInstanceAdmin?: boolean;
        keyId?: string;
        runId?: string;
        source?: "local_implicit" | "session" | "board_key" | "agent_key" | "agent_jwt" | "cloud_tenant" | "none";
      };
    }
  }
}
