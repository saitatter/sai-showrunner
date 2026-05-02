export type SatelliteConnectionService = "twitch"

export interface SatelliteConnectionRequestConfig {
	satelliteService: SatelliteConnectionService
	satelliteId: string
	ShowRunnerService: SatelliteConnectionService
	ShowRunnerId: string
	dashId: string
}

export interface SatelliteConnectionRequest extends SatelliteConnectionRequestConfig {
	sdp: RTCSessionDescriptionInit
}

export interface SatelliteConnectionResponse extends SatelliteConnectionRequestConfig {
	sdp: RTCSessionDescriptionInit
}

export interface SatelliteConnectionICECandidate extends SatelliteConnectionRequestConfig {
	side: "ShowRunner" | "satellite"
	candidate: RTCIceCandidateInit
}

export interface SatelliteConnectionOption {
	id: string

	remoteService: "twitch"
	remoteUserId: string
	remoteDisplayName: string
	remoteDisplayIcon: string

	type: string
	typeId: string

	name: string
}

export interface SatelliteConnectionInfo {
	id: string

	remoteService: SatelliteConnectionService
	remoteId: string
	type: string
	typeId: string
}
