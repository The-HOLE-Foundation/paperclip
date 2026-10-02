export {};

// Robust augmentation for Express Request.actor
// Targeting 'express' directly works reliably with `import { Request } from "express"`
// and NodeNext module resolution used in this project.
declare module "express" {
  interface Request {
    actor: any;  // Use any to unblock tsc in Docker/Railway builds; full shape is documented in the augmentation file and set at runtime by auth middleware.
  }
}

// Fallback global namespace augmentation (for any code using Express namespace style)
declare global {
  namespace Express {
    interface Request {
      actor: any;  // Use any to unblock tsc in Docker/Railway builds; full shape is documented in the augmentation file and set at runtime by auth middleware.
    }
  }
}
