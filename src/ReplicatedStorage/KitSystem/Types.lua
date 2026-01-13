local Types = {}

export type KitState = {
	kind: string?,
	equippedKitId: string?,
	ultimate: number?,
	abilityCooldownEndsAt: number?,
	serverNow: number?,
	lastAction: string?,
	lastError: string?,
}

export type KitEvent = {
	kind: string,
	event: string,
	playerId: number?,
	kitId: string?,
	effect: string?,
	abilityType: string?,
	inputState: any?,
	position: Vector3?,
	extraData: any?,
	serverTime: number?,
	reason: string?,
}

export type KitRequest = {
	action: string,
	kitId: string?,
	abilityType: string?,
	inputState: any?,
	extraData: any?,
}

export type KitContext = {
	player: Player,
	character: Model?,
	kitId: string,
	kitConfig: any,
	service: any,
}

export type ActionModule = {
	onStart: (self: ActionModule) -> (),
	onInterrupt: (self: ActionModule, reason: string) -> (),
	onEnd: (self: ActionModule) -> (),
}

export type KitModule = {
	new: (ctx: KitContext) -> KitModule,
	SetCharacter: (self: KitModule, character: Model?) -> (),
	Destroy: (self: KitModule) -> (),
	OnEquipped: (self: KitModule) -> (),
	OnUnequipped: (self: KitModule) -> (),
	OnAbility: (self: KitModule, inputState: any, extraData: any?) -> boolean,
	OnUltimate: (self: KitModule, inputState: any, extraData: any?) -> boolean,
}

return Types
