export type ErrorCode =
  | "bad_request"
  | "unauthorized"
  | "model_output_invalid"
  | "upstream_unavailable"
  | "rate_limited"
  | "internal";

export class ApiError extends Error {
  constructor(
    public readonly code: ErrorCode,
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export function toErrorBody(err: unknown): { status: number; body: { error: { code: string; message: string } } } {
  if (err instanceof ApiError) {
    return { status: err.status, body: { error: { code: err.code, message: err.message } } };
  }
  if (err instanceof Error && err.name === "ZodError") {
    return {
      status: 400,
      body: { error: { code: "bad_request", message: err.message } },
    };
  }
  console.error("unhandled", err);
  return {
    status: 500,
    body: { error: { code: "internal", message: "Internal error" } },
  };
}
