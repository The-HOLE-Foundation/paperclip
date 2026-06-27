export {};

// Robust augmentation for Express Request.actor
// Targeting 'express' directly works reliably with `import { Request } from "express"`
// and NodeNext module resolution used in this project.
declare module "express" {
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

// Fallback global namespace augmentation (for any code using Express namespace style)
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
