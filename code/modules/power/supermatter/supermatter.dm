//Ported from /vg/station13, which was in turn forked from baystation12;
//Please do not bother them with bugs from this port, however, as it has been modified quite a bit.
//Modifications include removing the world-ending full supermatter variation, and leaving only the shard.

GLOBAL_DATUM(main_supermatter_engine, /obj/machinery/power/supermatter_crystal)

/obj/machinery/power/supermatter_crystal
	name = "supermatter crystal"
	desc = "A strangely translucent and iridescent crystal."
	icon = 'icons/obj/supermatter.dmi'
	icon_state = "darkmatter"
	layer = ABOVE_MOB_LAYER
	density = TRUE
	anchored = TRUE
	appearance_flags = PIXEL_SCALE // no tile bound to allow distortion to render outside of direct view
	var/uid = 1
	var/static/gl_uid = 1
	light_range = 4
	// this thing bright as hell (to increase bloom)
	light_power = 5
	light_color = "#ffe016"
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF | FREEZE_PROOF
	flags_1 = PREVENT_CONTENTS_EXPLOSION_1
	critical_machine = TRUE
	interacts_with_air = TRUE

	var/gasefficency = 0.15

	base_icon_state = "darkmatter"

	var/final_countdown = FALSE

	var/damage = 0
	var/damage_archived = 0
	var/safe_alert = "Crystalline hyperstructure returning to safe operating parameters."
	var/warning_point = 50
	var/warning_alert = "Danger! Crystal hyperstructure integrity faltering!"
	var/damage_penalty_point = 550
	var/emergency_point = 700
	var/emergency_alert = "CRYSTAL DELAMINATION IMMINENT."
	var/explosion_point = 900

	var/emergency_issued = FALSE

	var/explosion_power = 35
	var/temp_factor = 30

	var/lastwarning = 0				// Time in 1/10th of seconds since the last sent warning
	var/power = 0

	/// Determines the maximum rate of positive change in gas comp values
	var/gas_change_rate = 0.05

	var/n2comp = 0					// raw composition of each gas in the chamber, ranges from 0 to 1

	var/plasmacomp = 0
	var/o2comp = 0
	var/co2comp = 0
	var/pluoxiumcomp = 0
	var/tritiumcomp = 0
	var/bzcomp = 0
	var/n2ocomp = 0

	var/combined_gas = 0
	var/gasmix_power_ratio = 0
	var/dynamic_heat_modifier = 1
	var/dynamic_heat_resistance = 1
	var/powerloss_inhibitor = 1
	var/powerloss_dynamic_scaling= 0
	var/power_transmission_bonus = 0
	var/mole_heat_penalty = 0


	var/matter_power = 0
	var/last_rads = 0

	//Temporary values so that we can optimize this
	//How much the bullets damage should be multiplied by when it is added to the internal variables
	var/config_bullet_energy = 2
	//How much of the power is left after processing is finished?
//	var/config_power_reduction_per_tick = 0.5
	//How much hallucination should it produce per unit of power?
	var/config_hallucination_power = 0.1

	var/obj/item/radio/radio
	var/radio_key = /obj/item/encryptionkey/headset_eng
	var/engineering_channel = "Engineering"
	var/common_channel = null

	//for logging
	var/has_been_powered = FALSE
	var/has_reached_emergency = FALSE

	///An effect we show to admins and ghosts the percentage of delam we're at
	var/obj/effect/countdown/supermatter/countdown

	var/is_main_engine = FALSE

	var/datum/looping_sound/supermatter/soundloop

	var/moveable = FALSE

	var/last_complete_process

	/// cooldown tracker for accent sounds,
	var/last_accent_sound = 0

	//For making hugbox supermatters
	///Disables all methods of taking damage
	var/takes_damage = TRUE
	///Disables the production of gas, and pretty much any handling of it we do.
	var/produces_gas = TRUE
	///Disables power changes
	var/power_changes = TRUE
	///Disables the sm's proccessing totally.
	var/processes = TRUE
	///Timer id for the disengage_field proc timer
	var/disengage_field_timer = null

	///Can the crystal trigger the station wide anomaly spawn?
	var/anomaly_event = TRUE

	/// don't let these to be consumed by SM
	var/static/list/not_dustable

	///Effect holder for the displacement filter to distort the SM based on its activity level
	var/atom/movable/distortion_effect/distort

	var/last_status

/atom/movable/distortion_effect
	name = ""
	plane = GRAVITY_PULSE_PLANE
	// Changing the colour of this based on the parent will cause issues with the displacement effect
	// so we need to ensure that it always has the default colour (clear).
	appearance_flags = PIXEL_SCALE | RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | NO_CLIENT_COLOR
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	icon = 'icons/effects/96x96.dmi'
	icon_state = "SM_base"
	pixel_x = -32
	pixel_y = -32

/obj/machinery/power/supermatter_crystal/Initialize(mapload)
	. = ..()
	uid = gl_uid++
	SSair.start_processing_machine(src)
	countdown = new(src)
	countdown.start()
	AddElement(/datum/element/point_of_interest)
	radio = new(src)
	radio.keyslot = new radio_key
	radio.set_listening(FALSE)
	radio.recalculateChannels()
	distort = new(src)
	add_emitter(/obj/emitter/sparkle, "supermatter_sparkle")
	investigate_log("has been created.", INVESTIGATE_ENGINES)
	if(is_main_engine)
		GLOB.main_supermatter_engine = src

	AddElement(/datum/element/bsa_blocker)
	RegisterSignal(src, COMSIG_ATOM_BSA_BEAM, PROC_REF(call_delamination_event))

	soundloop = new(src, TRUE)

	if(!not_dustable)
		not_dustable = typecacheof(list(
			/obj/eldritch,
			/obj/anomaly/singularity,
			/obj/anomaly/energy_ball,
			/obj/boh_tear
		))

/obj/machinery/power/supermatter_crystal/Destroy()
	investigate_log("has been destroyed.", INVESTIGATE_ENGINES)
	SSair.stop_processing_machine(src)
	QDEL_NULL(radio)
	QDEL_NULL(countdown)
	if(is_main_engine && GLOB.main_supermatter_engine == src)
		GLOB.main_supermatter_engine = null
	QDEL_NULL(soundloop)
	distort.icon = 'icons/effects/32x32.dmi'
	distort.icon_state = "SM_remnant"
	distort.pixel_x = 0
	distort.pixel_y = 0
	distort.forceMove(get_turf(src))
	distort = null
	return ..()

/obj/machinery/power/supermatter_crystal/examine(mob/user)
	. = ..()
	if(!user?.mind) // ghosts don't have mind
		return .
	var/immune = HAS_TRAIT(user, TRAIT_MADNESS_IMMUNE) || HAS_TRAIT(user.mind, TRAIT_MADNESS_IMMUNE)
	if (!isliving(user) && !immune && (get_dist(user, src) < HALLUCINATION_RANGE(power)))
		. += span_danger("You get headaches just from looking at it.")

// SupermatterMonitor UI for ghosts only. Inherited attack_ghost will call this.
/obj/machinery/power/supermatter_crystal/ui_interact(mob/user, datum/tgui/ui)
	if(!isobserver(user))
		return FALSE
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if (!ui)
		ui = new(user, src, "SupermatterMonitor")
		ui.set_autoupdate(TRUE)
		ui.open()

/obj/machinery/power/supermatter_crystal/ui_data(mob/user)
	var/list/data = list()
	var/turf/local_turf = get_turf(src)
	var/datum/gas_mixture/air = local_turf.return_air()
	// standalone_mode hides the "Back" button.
	data["standalone_mode"] = TRUE
	data["active"] = TRUE
	data["SM_integrity"] = get_integrity_percent()
	data["SM_power"] = power
	data["SM_radiation"] = last_rads
	data["SM_ambienttemp"] = air.return_temperature()
	data["SM_ambientpressure"] = air.return_pressure()
	data["SM_bad_moles_amount"] = MOLE_PENALTY_THRESHOLD / gasefficency
	data["SM_moles"] = 0
	var/list/gasdata = list()

	if(air.total_moles())
		data["SM_moles"] = air.total_moles()
		for(var/gasid in air.gases)
			gasdata.Add(list(list(
			"name"= air.gases[gasid][GAS_META][META_GAS_NAME],
			"amount" = round(100*air.gases[gasid][MOLES]/air.total_moles(),0.01))))

	else
		for(var/gasid in air.gases)
			gasdata.Add(list(list(
				"name"= air.gases[gasid][GAS_META][META_GAS_NAME],
				"amount" = 0,
				"id" = air.gases[gasid][GAS_META])))
	data["gases"] = gasdata
	return data

#define CRITICAL_TEMPERATURE 10000

/obj/machinery/power/supermatter_crystal/proc/get_status()
	var/turf/T = get_turf(src)
	if(!T)
		return SUPERMATTER_ERROR
	var/datum/gas_mixture/air = T.return_air()
	if(!air)
		return SUPERMATTER_ERROR

	var/integrity = get_integrity_percent()
	if(integrity < SUPERMATTER_DELAM_PERCENT)
		return SUPERMATTER_DELAMINATING

	if(integrity < SUPERMATTER_EMERGENCY_PERCENT)
		return SUPERMATTER_EMERGENCY

	if(integrity < SUPERMATTER_DANGER_PERCENT)
		return SUPERMATTER_DANGER

	if((integrity < SUPERMATTER_WARNING_PERCENT) || (air.return_temperature() > CRITICAL_TEMPERATURE))
		return SUPERMATTER_WARNING

	if(air.return_temperature() > (CRITICAL_TEMPERATURE * 0.8))
		return SUPERMATTER_NOTIFY

	if(power > 5)
		return SUPERMATTER_NORMAL
	return SUPERMATTER_INACTIVE

/obj/machinery/power/supermatter_crystal/proc/alarm()
	switch(get_status())
		if(SUPERMATTER_DELAMINATING)
			playsound(src, 'sound/misc/bloblarm.ogg', 100, FALSE, 40, 30, falloff_distance = 10)
		if(SUPERMATTER_EMERGENCY)
			playsound(src, 'sound/machines/engine_alert1.ogg', 100, FALSE, 30, 30, falloff_distance = 10)
		if(SUPERMATTER_DANGER)
			playsound(src, 'sound/machines/engine_alert2.ogg', 100, FALSE, 30, 30, falloff_distance = 10)
		if(SUPERMATTER_WARNING)
			playsound(src, 'sound/machines/terminal_alert.ogg', 75)

/obj/machinery/power/supermatter_crystal/proc/get_integrity_percent()
	var/integrity = damage / explosion_point
	integrity = round(100 - integrity * 100, 0.01)
	integrity = integrity < 0 ? 0 : integrity
	return integrity


/obj/machinery/power/supermatter_crystal/update_overlays()
	. = ..()
	. += get_displacement_icon()
	if(final_countdown)
		. += "causality_field"

// Switches the overlay based on the supermatter's current state; only called when the status has changed
/obj/machinery/power/supermatter_crystal/proc/get_displacement_icon()
	switch(last_status)
		if(SUPERMATTER_INACTIVE)
			distort.icon = 'icons/effects/96x96.dmi'
			distort.icon_state = "SM_base"
			distort.pixel_x = -32
			distort.pixel_y = -32
			light_range = 4
			light_power = 5
			light_color = "#ffe016"
		if(SUPERMATTER_NORMAL, SUPERMATTER_NOTIFY, SUPERMATTER_WARNING)
			distort.icon = 'icons/effects/96x96.dmi'
			distort.icon_state = "SM_base_active"
			distort.pixel_x = -32
			distort.pixel_y = -32
			light_range = 4
			light_power = 7
			light_color = "#ffe016"
		if(SUPERMATTER_DANGER)
			distort.icon = 'icons/effects/160x160.dmi'
			distort.icon_state = "SM_delam_1"
			distort.pixel_x = -64
			distort.pixel_y = -64
			light_range = 5
			light_power = 10
			light_color = "#ffb516"
		if(SUPERMATTER_EMERGENCY)
			distort.icon = 'icons/effects/224x224.dmi'
			distort.icon_state = "SM_delam_2"
			distort.pixel_x = -96
			distort.pixel_y = -96
			light_range = 6
			light_power = 10
			light_color = "#ff9208"
		if(SUPERMATTER_DELAMINATING)
			distort.icon = 'icons/effects/288x288.dmi'
			distort.icon_state = "SM_delam_3"
			distort.pixel_x = -128
			distort.pixel_y = -128
			light_range = 7
			light_power = 15
			light_color = "#ff5006"
	return distort

/obj/machinery/power/supermatter_crystal/proc/countdown()
	set waitfor = FALSE

	if(final_countdown) // We're already doing it go away
		return
	final_countdown = TRUE

	update_icon()

	var/speaking = "[emergency_alert] The supermatter has reached critical integrity failure. Emergency causality destabilization field has been activated."
	radio.talk_into(src, speaking, common_channel, language = get_selected_language())
	for(var/i in SUPERMATTER_COUNTDOWN_TIME to 0 step -10)
		if(damage < explosion_point) // Cutting it a bit close there engineers
			radio.talk_into(src, "[safe_alert] Failsafe has been disengaged.", common_channel)
			update_icon()
			final_countdown = FALSE
			return
		else if((i % 50) != 0 && i > 50) // A message once every 5 seconds until the final 5 seconds which count down individualy
			sleep(10)
			continue
		else if(i > 50)
			speaking = "[DisplayTimeText(i, TRUE)] remain before causality stabilization."
		else
			speaking = "[i*0.1]..."
		radio.talk_into(src, speaking, common_channel)
		sleep(10)

	delamination_event()

/obj/machinery/power/supermatter_crystal/proc/delamination_event()
	var/can_spawn_anomalies = is_station_level(loc.z) && is_main_engine && anomaly_event
	new /datum/supermatter_delamination(power, combined_gas, get_turf(src), explosion_power, gasmix_power_ratio, can_spawn_anomalies)

	if(combined_gas > MOLE_PENALTY_THRESHOLD) // kept as /datum does not inherit /investigate_log()
		investigate_log("has collapsed into a singularity.", INVESTIGATE_ENGINES)
	else if(power > POWER_PENALTY_THRESHOLD)
		investigate_log("has spawned additional energy balls.", INVESTIGATE_ENGINES)

	qdel(src)

//this is here to eat arguments
/obj/machinery/power/supermatter_crystal/proc/call_delamination_event()
	SIGNAL_HANDLER

	delamination_event()

/obj/machinery/power/supermatter_crystal/process_atmos()
	if(!processes) //Just fuck me up bro
		return
	var/turf/T = loc

	if(isnull(T))		// We have a null turf...something is wrong, stop processing this entity.
		return PROCESS_KILL

	if(!istype(T)) 	//We are in a crate or somewhere that isn't turf, if we return to turf resume processing but for now.
		return  //Yeah just stop.

	if(isclosedturf(T))
		var/turf/did_it_melt = T.Melt()
		if(!isclosedturf(did_it_melt)) //In case some joker finds way to place these on indestructible walls
			visible_message(span_warning("[src] melts through [T]!"))
		return

	if(last_complete_process > SSair.last_complete_process)
		power_changes = FALSE //Atmos has not been fully processed since the previous time the SM was. Abort all power and processing operations.
		return
	else
		power_changes = TRUE //Atmos has run at least one full tick recently, resume processing.

	if(power)
		soundloop.volume = clamp((50 + (power / 50)), 50, 100)
	if(damage >= 300)
		soundloop.mid_sounds = list('sound/machines/sm/loops/delamming.ogg' = 1)
	else
		soundloop.mid_sounds = list('sound/machines/sm/loops/calm.ogg' = 1)

	if(last_accent_sound < world.time && prob(20))
		var/aggression = min(((damage / 800) * (power / 2500)), 1.0) * 100
		if(damage >= 300)
			playsound(src, "smdelam", max(50, aggression), FALSE, 40, 30, falloff_distance = 10)
		else
			playsound(src, "smcalm", max(50, aggression), FALSE, 25, 25, falloff_distance = 10)
		var/next_sound = round((100 - aggression) * 5)
		last_accent_sound = world.time + max(SUPERMATTER_ACCENT_SOUND_MIN_COOLDOWN, next_sound)

	//Ok, get the air from the turf
	var/datum/gas_mixture/env = T.return_air()

	var/datum/gas_mixture/removed

	if(produces_gas)
		//Remove gas from surrounding area
		removed = env.remove_ratio(gasefficency)
	else
		// Pass all the gas related code an empty gas container
		removed = new()

	damage_archived = damage
	if(!removed || !removed.total_moles() || isspaceturf(T)) //we're in space or there is no gas to process
		if(takes_damage)
			damage += max((power / 1000) * DAMAGE_INCREASE_MULTIPLIER, 0.1) // always does at least some damage
	else
		if(takes_damage)
			//causing damage
			damage = max(damage + (max(clamp(removed.total_moles() / 200, 0.5, 1) * removed.return_temperature() - ((T0C + HEAT_PENALTY_THRESHOLD)*dynamic_heat_resistance), 0) * mole_heat_penalty / 150 ) * DAMAGE_INCREASE_MULTIPLIER, 0)
			damage = max(damage + (max(power - POWER_PENALTY_THRESHOLD, 0)/500) * DAMAGE_INCREASE_MULTIPLIER, 0)
			damage = max(damage + (max(combined_gas - MOLE_PENALTY_THRESHOLD, 0)/80) * DAMAGE_INCREASE_MULTIPLIER, 0)

			//healing damage
			if(combined_gas < MOLE_PENALTY_THRESHOLD)
				damage = max(damage + (min(removed.return_temperature() - (T0C + HEAT_PENALTY_THRESHOLD), 0) / 150 ), 0)

			//capping damage
			damage = min(damage_archived + (DAMAGE_HARDCAP * explosion_point),damage)

		//calculating gas related values
		combined_gas = max(removed.total_moles(), 0)

		//This is more error prevention, according to all known laws of atmos, gas_mix.remove() should never make negative mol values.
		//But this is tg
		//Lets get the proportions of the gasses in the mix for scaling stuff later
		//They range between 0 and 1
		plasmacomp += clamp(max(GET_MOLES(/datum/gas/plasma, removed)/combined_gas, 0) - plasmacomp, -1, gas_change_rate)
		o2comp += clamp(max(GET_MOLES(/datum/gas/oxygen, removed)/combined_gas, 0) - o2comp, -1, gas_change_rate)
		co2comp += clamp(max(GET_MOLES(/datum/gas/carbon_dioxide, removed)/combined_gas, 0) - co2comp, -1, gas_change_rate)
		pluoxiumcomp += clamp(max(GET_MOLES(/datum/gas/pluoxium, removed)/combined_gas, 0) - pluoxiumcomp, -1, gas_change_rate)
		tritiumcomp += clamp(max(GET_MOLES(/datum/gas/tritium, removed)/combined_gas, 0) - tritiumcomp, -1, gas_change_rate)
		bzcomp += clamp(max(GET_MOLES(/datum/gas/bz, removed)/combined_gas, 0) - bzcomp, -1, gas_change_rate)

		n2ocomp += clamp(max(GET_MOLES(/datum/gas/nitrous_oxide, removed)/combined_gas, 0) - n2ocomp, -1, gas_change_rate)
		n2comp += clamp(max(GET_MOLES(/datum/gas/nitrogen, removed)/combined_gas, 0) - n2comp, -1, gas_change_rate)

		gasmix_power_ratio = min(max(plasmacomp + o2comp + co2comp + tritiumcomp + bzcomp - pluoxiumcomp - n2comp, 0), 1)

		dynamic_heat_modifier = max((plasmacomp * PLASMA_HEAT_PENALTY) + (o2comp * OXYGEN_HEAT_PENALTY) + (co2comp * CO2_HEAT_PENALTY) + (tritiumcomp * TRITIUM_HEAT_PENALTY) + (pluoxiumcomp * PLUOXIUM_HEAT_PENALTY) + (n2comp * NITROGEN_HEAT_PENALTY) + (bzcomp * BZ_HEAT_PENALTY), 0.5)
		dynamic_heat_resistance = max((n2ocomp * N2O_HEAT_RESISTANCE) + (pluoxiumcomp * PLUOXIUM_HEAT_RESISTANCE), 1)

		power_transmission_bonus = 1 + max((plasmacomp * PLASMA_TRANSMIT_MODIFIER) + (o2comp * OXYGEN_TRANSMIT_MODIFIER), 0)

		//Let's say that the CO2 touches the SM surface and the radiation turns it into Pluoxium.
		if(co2comp && o2comp)
			var/carbon_dioxide_pp = env.return_pressure() * co2comp
			var/consumed_carbon_dioxide = clamp(((carbon_dioxide_pp - CO2_CONSUMPTION_PP) / (carbon_dioxide_pp + CO2_PRESSURE_SCALING)), CO2_CONSUMPTION_RATIO_MIN, CO2_CONSUMPTION_RATIO_MAX)
			consumed_carbon_dioxide = min(consumed_carbon_dioxide * co2comp * combined_gas, removed.gases[/datum/gas/carbon_dioxide][MOLES] * INVERSE(0.5), removed.gases[/datum/gas/oxygen][MOLES] * INVERSE(0.5))
			if(consumed_carbon_dioxide)
				REMOVE_MOLES(/datum/gas/carbon_dioxide, removed, consumed_carbon_dioxide * 0.5)
				REMOVE_MOLES(/datum/gas/oxygen, removed, consumed_carbon_dioxide * 0.5)
				ADD_MOLES(/datum/gas/pluoxium, removed, consumed_carbon_dioxide * 0.25)

		//more moles of gases are harder to heat than fewer, so let's scale heat damage around them
		mole_heat_penalty = max(combined_gas / MOLE_HEAT_PENALTY, 0.25)

		if (combined_gas > POWERLOSS_INHIBITION_MOLE_THRESHOLD && co2comp > POWERLOSS_INHIBITION_GAS_THRESHOLD)
			powerloss_dynamic_scaling = clamp(powerloss_dynamic_scaling + clamp(co2comp - powerloss_dynamic_scaling, -0.02, 0.02), 0, 1)
		else
			powerloss_dynamic_scaling = clamp(powerloss_dynamic_scaling - 0.05,0, 1)
		powerloss_inhibitor = clamp(1-(powerloss_dynamic_scaling * clamp(combined_gas/POWERLOSS_INHIBITION_MOLE_BOOST_THRESHOLD,1 ,1.5)),0 ,1)

		if(matter_power)
			var/removed_matter = max(matter_power/MATTER_POWER_CONVERSION, 40)
			power = max(power + removed_matter, 0)
			matter_power = max(matter_power - removed_matter, 0)

		var/temp_factor = 50

		if(gasmix_power_ratio > 0.8)
			// with a perfect gas mix, make the power less based on heat
			icon_state = "[base_icon_state]_glow"
		else
			// in normal mode, base the produced energy around the heat
			temp_factor = 30
			icon_state = base_icon_state

		power = clamp((removed.return_temperature() * temp_factor / T0C) * gasmix_power_ratio + power, 0, SUPERMATTER_MAXIMUM_ENERGY) //Total laser power plus an overload

		if(prob(50))
			last_rads = power * max(0, power_transmission_bonus * (1 + (tritiumcomp * TRITIUM_RADIOACTIVITY_MODIFIER) + (pluoxiumcomp * PLUOXIUM_RADIOACTIVITY_MODIFIER) + (bzcomp * BZ_RADIOACTIVITY_MODIFIER)))
			radiation_pulse(src, last_rads)
		if(bzcomp >= 0.4 && prob(30 * bzcomp))
			src.fire_nuclear_particle()		// Start to emit radballs at a maximum of 30% chance per tick


		var/device_energy = power * REACTION_POWER_MODIFIER

		//To figure out how much temperature to add each tick, consider that at one atmosphere's worth
		//of pure oxygen, with all four lasers firing at standard energy and no N2 present, at room temperature
		//that the device energy is around 2140. At that stage, we don't want too much heat to be put out
		//Since the core is effectively "cold"

		//Also keep in mind we are only adding this temperature to (efficiency)% of the one tile the rock
		//is on. An increase of 4*C @ 25% efficiency here results in an increase of 1*C / (#tilesincore) overall.
		removed.temperature = (removed.return_temperature() + ((device_energy * dynamic_heat_modifier) / THERMAL_RELEASE_MODIFIER))

		removed.temperature = (max(0, min(removed.return_temperature(), 2500 * dynamic_heat_modifier)))

		//Calculate how much gas to release
		ADD_MOLES(/datum/gas/plasma, removed, max((device_energy * dynamic_heat_modifier) / PLASMA_RELEASE_MODIFIER, 0))

		ADD_MOLES(/datum/gas/oxygen, removed, max(((device_energy + removed.return_temperature() * dynamic_heat_modifier) - T0C) / OXYGEN_RELEASE_MODIFIER, 0))

		removed.garbage_collect()

		if(produces_gas)
			env.merge(removed)
			air_update_turf(FALSE, FALSE)

	for(var/mob/living/carbon/human/l in viewers(HALLUCINATION_RANGE(power), src)) // If they can see it without mesons on.  Bad on them.
		if(HAS_TRAIT(l, TRAIT_MADNESS_IMMUNE) || (l.mind && HAS_TRAIT(l.mind, TRAIT_MADNESS_IMMUNE)))
			continue
		var/D = sqrt(1 / max(1, get_dist(l, src)))
		l.hallucination += power * config_hallucination_power * D
		l.hallucination = clamp(0, 200, l.hallucination)

	// Checks if the status has changed, in order to update the displacement effect
	var/current_status = get_status()
	if(current_status != last_status)
		last_status = current_status
		update_icon(UPDATE_OVERLAYS)

	//Transitions between one function and another, one we use for the fast inital startup, the other is used to prevent errors with fusion temperatures.
	//Use of the second function improves the power gain imparted by using co2
	if(is_power_processing())
		power =  max(power - min(((power/500)**3) * powerloss_inhibitor, power * 0.83 * powerloss_inhibitor),0)

	if(power > POWER_PENALTY_THRESHOLD || damage > damage_penalty_point)

		if(power > POWER_PENALTY_THRESHOLD)
			playsound(src.loc, 'sound/weapons/emitter2.ogg', 100, 1, extrarange = 10)
			supermatter_zap(src, 5, min(power*2, 20000))
			supermatter_zap(src, 5, min(power*2, 20000))
			if(power > SEVERE_POWER_PENALTY_THRESHOLD)
				supermatter_zap(src, 5, min(power*2, 20000))
				if(power > CRITICAL_POWER_PENALTY_THRESHOLD)
					supermatter_zap(src, 5, min(power*2, 20000))
		else if (damage > damage_penalty_point && prob(20))
			playsound(src.loc, 'sound/weapons/emitter2.ogg', 100, 1, extrarange = 10)
			supermatter_zap(src, 5, clamp(power*2, 4000, 20000))

		if(prob(15) && power > POWER_PENALTY_THRESHOLD)
			supermatter_pull(src, power/750)
		if(prob(5))
			supermatter_anomaly_gen(src, ANOMALY_FLUX, rand(5, 10))
		if(prob(5))
			supermatter_anomaly_gen(src, ANOMALY_HALLUCINATION, rand(5, 10))
		if(power > SEVERE_POWER_PENALTY_THRESHOLD && prob(5) || prob(1))
			supermatter_anomaly_gen(src, ANOMALY_GRAVITATIONAL, rand(5, 10))
		if(power > SEVERE_POWER_PENALTY_THRESHOLD && prob(2) || prob(0.3) && power > POWER_PENALTY_THRESHOLD)
			supermatter_anomaly_gen(src, ANOMALY_PYRO, rand(5, 10))

	if(damage > warning_point) // while the core is still damaged and it's still worth noting its status
		if(damage_archived < warning_point) //If damage_archive is under the warning point, this is the very first cycle that we've reached said point.
			SEND_SIGNAL(src, COMSIG_SUPERMATTER_DELAM_START_ALARM)
		if((REALTIMEOFDAY - lastwarning) / 10 >= WARNING_DELAY)
			alarm()

			if(damage > emergency_point)
				radio.talk_into(src, "[emergency_alert] Integrity: [get_integrity_percent()]%", common_channel)
				SEND_SIGNAL(src, COMSIG_SUPERMATTER_DELAM_ALARM)
				lastwarning = REALTIMEOFDAY
				if(!has_reached_emergency)
					investigate_log("has reached the emergency point for the first time.", INVESTIGATE_ENGINES)
					message_admins("[src] has reached the emergency point [ADMIN_JMP(src)].")
					has_reached_emergency = TRUE
			else if(damage >= damage_archived) // The damage is still going up
				radio.talk_into(src, "[warning_alert] Integrity: [get_integrity_percent()]%", engineering_channel)
				SEND_SIGNAL(src, COMSIG_SUPERMATTER_DELAM_ALARM)
				lastwarning = REALTIMEOFDAY - (WARNING_DELAY * 5)

			else                                                 // Phew, we're safe
				radio.talk_into(src, "[safe_alert] Integrity: [get_integrity_percent()]%", engineering_channel)
				lastwarning = REALTIMEOFDAY

			if(power > POWER_PENALTY_THRESHOLD)
				radio.talk_into(src, "Warning: Hyperstructure has reached dangerous power level.", engineering_channel)
				if(powerloss_inhibitor < 0.5)
					radio.talk_into(src, "DANGER: CHARGE INERTIA CHAIN REACTION IN PROGRESS.", engineering_channel)

			if(combined_gas > MOLE_PENALTY_THRESHOLD)
				radio.talk_into(src, "Warning: Critical coolant mass reached.", engineering_channel)

		if(damage > explosion_point)
			countdown()

	last_complete_process = world.time
	return 1

/obj/machinery/power/supermatter_crystal/bullet_act(obj/projectile/Proj)
	var/turf/L = loc
	if(!istype(L))
		return FALSE
	if(!istype(Proj.firer, /obj/machinery/power/emitter))
		investigate_log("has been hit by [Proj] fired by [key_name(Proj.firer)]", INVESTIGATE_ENGINES)
	if(Proj.armor_flag != BULLET)
		if(is_power_processing()) //This needs to be here I swear //Okay bro, but I'm taking the other check because it definitely doesn't.
			power += Proj.damage * config_bullet_energy
			if(!has_been_powered)
				investigate_log("has been powered for the first time.", INVESTIGATE_ENGINES)
				message_admins("[src] has been powered for the first time [ADMIN_JMP(src)].")
				has_been_powered = TRUE
	else if(takes_damage)
		damage += Proj.damage * config_bullet_energy
	return BULLET_ACT_HIT

/obj/machinery/power/supermatter_crystal/singularity_act()
	var/gain = 100
	investigate_log("Supermatter shard consumed by singularity.", INVESTIGATE_ENGINES)
	message_admins("Singularity has consumed a supermatter shard and can now become stage six.")
	visible_message(span_userdanger("[src] is consumed by the singularity!"))
	for(var/mob/M in GLOB.player_list)
		if(M.get_virtual_z_level() == get_virtual_z_level())
			SEND_SOUND(M, 'sound/effects/supermatter.ogg') //everyone goan know bout this
			to_chat(M, span_boldannounce("A horrible screeching fills your ears, and a wave of dread washes over you..."))
	qdel(src)
	return gain

/obj/machinery/power/supermatter_crystal/blob_act(obj/structure/blob/blob)
	if(!blob || isspaceturf(loc)) //does nothing in space
		return
	playsound(get_turf(src), 'sound/effects/supermatter.ogg', 50, TRUE)
	damage += blob.get_integrity() * 0.5 //take damage equal to 50% of remaining blob health before it tried to eat us
	if(blob.get_integrity() > 100)
		blob.visible_message(span_danger("\The [blob] strikes at \the [src] and flinches away!"),\
		span_italics("You hear a loud crack as you are washed with a wave of heat."))
		blob.take_damage(100, BURN)
	else
		blob.visible_message(span_danger("\The [blob] strikes at \the [src] and rapidly flashes to ash."),\
		span_italics("You hear a loud crack as you are washed with a wave of heat."))
		Consume(blob)

/obj/machinery/power/supermatter_crystal/attack_tk(mob/user)
	if(!iscarbon(user))
		return
	var/mob/living/carbon/jedi = user
	to_chat(jedi, span_userdanger("That was a really dense idea."))
	jedi.ghostize()
	var/obj/item/organ/brain/rip_u = locate(/obj/item/organ/brain) in jedi.internal_organs
	if(rip_u)
		rip_u.Remove(jedi)
		qdel(rip_u)
	return COMPONENT_CANCEL_ATTACK_CHAIN

/obj/machinery/power/supermatter_crystal/attack_paw(mob/user)
	dust_mob(user, cause = "monkey attack")

/obj/machinery/power/supermatter_crystal/attack_alien(mob/user)
	dust_mob(user, cause = "alien attack")

/obj/machinery/power/supermatter_crystal/attack_animal(mob/living/simple_animal/S)
	var/murder
	if(!S.melee_damage)
		murder = S.friendly_verb_continuous
	else
		murder = S.attack_verb_continuous
	dust_mob(S, \
	span_danger("[S] unwisely [murder] [src], and [S.p_their()] body burns brilliantly before flashing into ash!"), \
	span_userdanger("You unwisely touch [src], and your vision glows brightly as your body crumbles to dust. Oops."), \
	"simple animal attack")

/obj/machinery/power/supermatter_crystal/attack_robot(mob/user)
	if(Adjacent(user))
		dust_mob(user, cause = "cyborg attack")

/obj/machinery/power/supermatter_crystal/attack_ai(mob/user)
	return

/obj/machinery/power/supermatter_crystal/attack_hand(mob/living/user)
	. = ..()
	if(.)
		return
	dust_mob(user, cause = "hand")

/obj/machinery/power/supermatter_crystal/proc/dust_mob(mob/living/nom, vis_msg, mob_msg, cause)
	if(nom.incorporeal_move || nom.status_flags & GODMODE || is_type_in_typecache(nom, not_dustable))
		return
	if(!vis_msg)
		vis_msg = span_danger("[nom] reaches out and touches [src], inducing a resonance... [nom.p_their()] body starts to glow and burst into flames before flashing into dust!")
	if(!mob_msg)
		mob_msg = span_userdanger("You reach out and touch [src]. Everything starts burning and all you can hear is ringing. Your last thought is \"That was not a wise decision.\"")
	if(!cause)
		cause = "contact"
	nom.visible_message(vis_msg, mob_msg, span_italics("You hear an unearthly noise as a wave of heat washes over you."))
	investigate_log("has been attacked ([cause]) by [key_name(nom)]", INVESTIGATE_ENGINES)
	playsound(get_turf(src), 'sound/effects/supermatter.ogg', 50, 1)
	Consume(nom)

/obj/machinery/power/supermatter_crystal/attackby(obj/item/W, mob/living/user, params)
	if(!istype(W) || (W.item_flags & ABSTRACT) || !istype(user))
		return
	if(is_type_in_typecache(W, not_dustable))
		return ..()
	if(istype(W, /obj/item/melee/roastingstick)) // SM Cooking 101
		return ..()
	if(istype(W, /obj/item/clothing/mask/cigarette))
		var/obj/item/clothing/mask/cigarette/cig = W
		var/clumsy = HAS_TRAIT(user, TRAIT_CLUMSY)
		if(clumsy)
			var/which_hand = BODY_ZONE_L_ARM
			if(!(user.active_hand_index % 2))
				which_hand = BODY_ZONE_R_ARM
			var/obj/item/bodypart/dust_arm = user.get_bodypart(which_hand)
			dust_arm.dismember()
			user.visible_message(span_danger("The [W] flashes out of existence on contact with \the [src], resonating with a horrible sound..."),\
				span_danger("Oops! The [W] flashes out of existence on contact with \the [src], taking your arm with it! That was clumsy of you!"))
			playsound(src, 'sound/effects/supermatter.ogg', 150, 1)
			Consume(dust_arm)
			Consume(W)
			return
		if(cig.lit || user.combat_mode)
			user.visible_message(span_danger("A hideous sound echoes as [W] is ashed out on contact with \the [src]. That didn't seem like a good idea..."))
			playsound(src, 'sound/effects/supermatter.ogg', 150, 1)
			Consume(W)
			radiation_pulse(src, 150, 4)
			return ..()
		else
			cig.light()
			user.visible_message(span_danger("As [user] lights \their [W] on \the [src], silence fills the room..."),\
				span_danger("Time seems to slow to a crawl as you touch \the [src] with \the [W].") + "\n" + span_notice("\The [W] flashes alight with an eerie energy as you nonchalantly lift your hand away from \the [src]. Damn."))
			playsound(src, 'sound/effects/supermatter.ogg', 50, 1)
			radiation_pulse(src, 50, 3)
			return
	if(istype(W, /obj/item/scalpel/supermatter))
		var/obj/item/scalpel/supermatter/scalpel = W
		to_chat(user, span_notice("You carefully begin to scrape \the [src] with \the [W]..."))
		if(W.use_tool(src, user, 60, volume=100))
			if (scalpel.usesLeft)
				to_chat(user, span_danger("You extract a sliver from \the [src]. \The [src] begins to react violently!"))
				new /obj/item/nuke_core/supermatter_sliver(drop_location())
				matter_power += 800
				scalpel.usesLeft--
				if (!scalpel.usesLeft)
					to_chat(user, span_notice("A tiny piece of \the [W] falls off, rendering it useless!"))
			else
				to_chat(user, span_notice("You fail to extract a sliver from \The [src]. \the [W] isn't sharp enough anymore!"))
	else if(user.dropItemToGround(W))
		user.visible_message(span_danger("As [user] touches \the [src] with \a [W], silence fills the room..."),\
			span_userdanger("You touch \the [src] with \the [W], and everything suddenly goes silent.") + "\n" + span_notice("The [W] flashes into dust as you flinch away from \the [src]."),\
			span_italics("Everything suddenly goes silent."))
		investigate_log("has been attacked ([W]) by [key_name(user)]", INVESTIGATE_ENGINES)
		Consume(W)
		playsound(get_turf(src), 'sound/effects/supermatter.ogg', 50, 1)

		radiation_pulse(src, 150, 4)

/obj/machinery/power/supermatter_crystal/wrench_act(mob/user, obj/item/tool)
	if (moveable)
		default_unfasten_wrench(user, tool, time = 20)
	return TRUE

/obj/machinery/power/supermatter_crystal/Bumped(atom/movable/AM)
	if(is_type_in_typecache(AM, not_dustable))
		return ..() // remove calling parent if it causes weird behaviour
	else if(isliving(AM))
		AM.visible_message(span_danger("\The [AM] slams into \the [src] inducing a resonance... [AM.p_their()] body starts to glow and burst into flames before flashing into dust!"),\
		span_userdanger("You slam into \the [src] as your ears are filled with unearthly ringing. Your last thought is \"Oh, fuck.\""),\
		span_italics("You hear an unearthly noise as a wave of heat washes over you."))
	else if(isobj(AM) && !iseffect(AM))
		AM.visible_message(span_danger("\The [AM] smacks into \the [src] and rapidly flashes to ash."), null,\
		span_italics("You hear a loud crack as you are washed with a wave of heat."))
	else
		return

	playsound(get_turf(src), 'sound/effects/supermatter.ogg', 50, 1)

	Consume(AM)

/obj/machinery/power/supermatter_crystal/intercept_zImpact(atom/movable/AM, levels)
	. = ..()
	Bumped(AM)
	. |= FALL_STOP_INTERCEPTING | FALL_INTERCEPTED

/obj/machinery/power/supermatter_crystal/proc/Consume(atom/movable/AM)
	if(is_type_in_typecache(AM, not_dustable))
		return
	else if(isliving(AM))
		var/mob/living/user = AM
		if(user.status_flags & GODMODE)
			return
		message_admins("[src] has consumed [key_name_admin(user)] [ADMIN_JMP(src)].")
		investigate_log("has consumed [key_name(user)].", INVESTIGATE_ENGINES)
		user.investigate_log("has been dusted by [src].", INVESTIGATE_DEATHS)
		user.dust(force = TRUE)
		if(is_power_processing())
			matter_power += 200
	else if(isobj(AM))
		var/obj/O = AM
		if(O.resistance_flags & INDESTRUCTIBLE)
			if(!disengage_field_timer) //we really don't want to have more than 1 timer and causality field overlayer at once
				update_icon()
				radio.talk_into(src, "Anomalous object has breached containment, emergency causality field enganged to prevent reality destabilization.", engineering_channel)
				disengage_field_timer = addtimer(CALLBACK(src, PROC_REF(disengage_field)), 5 SECONDS)
			return
		if(!iseffect(AM))
			var/suspicion = ""
			if(AM.fingerprintslast)
				suspicion = "last touched by [AM.fingerprintslast]"
				message_admins("[src] has consumed [AM], [suspicion] [ADMIN_JMP(src)].")
			investigate_log("has consumed [AM] - [suspicion].", INVESTIGATE_ENGINES)
		qdel(AM)
	if(!iseffect(AM) && is_power_processing())
		matter_power += 200

	//Some poor sod got eaten, go ahead and irradiate people nearby.
	radiation_pulse(src, 3000, 2, TRUE)
	for(var/mob/living/L in range(10))
		investigate_log("has irradiated [key_name(L)] after consuming [AM].", INVESTIGATE_ENGINES)
		if(L in viewers(get_turf(src)))
			L.show_message(span_danger("As \the [src] slowly stops resonating, you find your skin covered in new radiation burns."), 1,\
				span_danger("The unearthly ringing subsides and you notice you have new radiation burns."), MSG_AUDIBLE)
		else
			L.show_message(span_italics("You hear an unearthly ringing and notice your skin is covered in fresh radiation burns."), MSG_AUDIBLE)

/obj/machinery/power/supermatter_crystal/proc/disengage_field()
	if(QDELETED(src))
		return
	update_icon()
	disengage_field_timer = null

//Do not blow up our internal radio
/obj/machinery/power/supermatter_crystal/contents_explosion(severity, target)
	return

/obj/machinery/power/supermatter_crystal/engine
	is_main_engine = TRUE

/obj/machinery/power/supermatter_crystal/shard
	name = "supermatter shard"
	desc = "A strangely translucent and iridescent crystal that looks like it used to be part of a larger structure."
	base_icon_state = "darkmatter_shard"
	icon_state = "darkmatter_shard"
	anchored = FALSE
	gasefficency = 0.125
	explosion_power = 12
	layer = ABOVE_MOB_LAYER
	moveable = TRUE
	anomaly_event = FALSE

/obj/machinery/power/supermatter_crystal/shard/engine
	name = "anchored supermatter shard"
	is_main_engine = TRUE
	anchored = TRUE
	moveable = FALSE

// When you wanna make a supermatter shard for the dramatic effect, but
// don't want it exploding suddenly
/obj/machinery/power/supermatter_crystal/shard/hugbox
	name = "anchored supermatter shard"
	takes_damage = FALSE
	produces_gas = FALSE
	processes = FALSE //SHUT IT DOWN
	moveable = FALSE
	anchored = TRUE

/obj/machinery/power/supermatter_crystal/shard/hugbox/fakecrystal //Hugbox shard with crystal visuals, used in the Supermatter/Hyperfractal shuttle
	name = "supermatter crystal"
	base_icon_state = "darkmatter"
	icon_state = "darkmatter"

/obj/machinery/power/supermatter_crystal/proc/supermatter_pull(turf/center, pull_range = 10)
	playsound(src.loc, 'sound/weapons/marauder.ogg', 100, TRUE, extrarange = 7)
	for(var/atom/movable/P in orange(pull_range,center))
		if(P.anchored || P.move_resist >= MOVE_FORCE_EXTREMELY_STRONG) //move resist memes.
			return
		if(ishuman(P))
			var/mob/living/carbon/human/H = P
			if(H.incapacitated() || H.body_position == LYING_DOWN || H.mob_negates_gravity())
				return //You can't knock down someone who is already knocked down or has immunity to gravity
			H.visible_message(span_danger("[H] is suddenly knocked down, as if [H.p_their()] [(H.usable_legs == 1) ? "leg had" : "legs have"] been pulled out from underneath [H.p_them()]!"),\
				span_userdanger("A sudden gravitational pulse knocks you down!"),\
				span_italics("You hear a thud."))
			H.apply_effect(40, EFFECT_PARALYZE, 0)
		else //you're not human so you get sucked in
			step_towards(P,center)
			step_towards(P,center)
			step_towards(P,center)
			step_towards(P,center)

/proc/supermatter_anomaly_gen(turf/anomalycenter, type = ANOMALY_FLUX, anomalyrange = 5, has_weak_lifespan = TRUE)
	var/turf/local_turf = pick(RANGE_TURFS(anomalyrange, anomalycenter) - anomalycenter)
	if(!local_turf)
		return
	var/faked_reality_spawn = pick(0, 1)
	switch(type)
		if(ANOMALY_BIOSCRAMBLER)
			new /obj/effect/anomaly/bioscrambler(local_turf, null, faked_reality_spawn)
		if(ANOMALY_FLUX)
			var/explosive = has_weak_lifespan ? ANOMALY_FLUX_NO_EXPLOSION : ANOMALY_FLUX_LOW_EXPLOSIVE
			new /obj/effect/anomaly/flux(local_turf, has_weak_lifespan ? rand(250, 300) : null, TRUE, explosive, faked_reality_spawn)
		if(ANOMALY_GRAVITATIONAL)
			new /obj/effect/anomaly/grav(local_turf, has_weak_lifespan ? rand(200, 300) : null, faked_reality_spawn)
		if(ANOMALY_HALLUCINATION)
			new /obj/effect/anomaly/hallucination(local_turf, has_weak_lifespan ? rand(150, 250) : null, faked_reality_spawn)
		if(ANOMALY_PYRO)
			new /obj/effect/anomaly/pyro(local_turf, has_weak_lifespan ? rand(150, 250) : null, faked_reality_spawn)
		if(ANOMALY_VORTEX)
			new /obj/effect/anomaly/bhole(local_turf, 20, faked_reality_spawn)

/obj/machinery/power/supermatter_crystal/proc/supermatter_zap(atom/zapstart, range = 3, power)
	. = zapstart.dir
	if(power < 1000)
		return

	var/target_atom
	var/mob/living/target_mob
	var/obj/machinery/target_machine
	var/obj/structure/target_structure
	var/list/arctargetsmob = list()
	var/list/arctargetsmachine = list()
	var/list/arctargetsstructure = list()

	if(prob(20)) //let's not hit all the engineers with every beam and/or segment of the arc
		for(var/mob/living/Z in ohearers(range+2, zapstart))
			arctargetsmob += Z
	if(arctargetsmob.len)
		var/mob/living/H = pick(arctargetsmob)
		var/atom/A = H
		target_mob = H
		target_atom = A

	else
		for(var/obj/machinery/X in oview(range+2, zapstart))
			arctargetsmachine += X
		if(arctargetsmachine.len)
			var/obj/machinery/M = pick(arctargetsmachine)
			var/atom/A = M
			target_machine = M
			target_atom = A

		else
			for(var/obj/structure/Y in oview(range+2, zapstart))
				arctargetsstructure += Y
			if(arctargetsstructure.len)
				var/obj/structure/O = pick(arctargetsstructure)
				var/atom/A = O
				target_structure = O
				target_atom = A

	if(target_atom)
		zapstart.Beam(target_atom, icon_state="nzcrentrs_power", time=5)
		var/zapdir = get_dir(zapstart, target_atom)
		if(zapdir)
			. = zapdir

	if(target_mob)
		target_mob.electrocute_act(rand(5,10), "Supermatter Discharge Bolt", 1, SHOCK_NOSTUN)
		if(prob(15))
			supermatter_zap(target_mob, 5, power / 2)
			supermatter_zap(target_mob, 5, power / 2)
		else
			supermatter_zap(target_mob, 5, power / 1.5)

	else if(target_machine)
		if(prob(15))
			supermatter_zap(target_machine, 5, power / 2)
			supermatter_zap(target_machine, 5, power / 2)
		else
			supermatter_zap(target_machine, 5, power / 1.5)

	else if(target_structure)
		if(prob(15))
			supermatter_zap(target_structure, 5, power / 2)
			supermatter_zap(target_structure, 5, power / 2)
		else
			supermatter_zap(target_structure, 5, power / 1.5)

/obj/machinery/power/supermatter_crystal/proc/is_power_processing()
	if(!power_changes) //Still toggled off from a failed atmos tick at some point
		return FALSE
	if(SSair.state >= SS_PAUSED) //Atmos isn't running, stop building power until it is fully operational again
		power_changes = FALSE
		return FALSE
	else //Atmos is either operational, or hasn't been stumbling enough for it to matter yet
		return TRUE

#undef HALLUCINATION_RANGE

#undef CRITICAL_TEMPERATURE
