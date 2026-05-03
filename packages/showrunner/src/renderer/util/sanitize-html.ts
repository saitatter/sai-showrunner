import DOMPurify from "dompurify"

export function sanitizeReleaseNotes(notes: string) {
	return DOMPurify.sanitize(notes, {
		USE_PROFILES: { html: true },
		ADD_ATTR: ["target", "rel"],
	})
}
