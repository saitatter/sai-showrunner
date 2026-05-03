import DOMPurify from "dompurify"
import { UpdateData } from "showrunner-schema"

export function sanitizeReleaseNotes(notes: string) {
	return DOMPurify.sanitize(notes, {
		USE_PROFILES: { html: true },
		ADD_ATTR: ["target", "rel"],
	})
}

export function releaseNotesToSanitizedHtml(updateData: UpdateData | undefined) {
	const html = updateData?.releaseNotes?.length
		? updateData.releaseNotes
			.map((releaseNote) => {
				const title = releaseNote.version ? `<h3>${escapeHtml(releaseNote.version)}</h3>` : ""
				return `${title}${releaseNote.note ?? ""}`
			})
			.join("\n")
		: updateData?.notes ?? ""

	return sanitizeReleaseNotes(html)
}

function escapeHtml(value: string) {
	return value
		.replaceAll("&", "&amp;")
		.replaceAll("<", "&lt;")
		.replaceAll(">", "&gt;")
		.replaceAll('"', "&quot;")
		.replaceAll("'", "&#039;")
}
