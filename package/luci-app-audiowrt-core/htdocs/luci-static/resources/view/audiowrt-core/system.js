'use strict';
'require view';
'require uci';
'require fs';
'require ui';
return view.extend({
	load:function(){return Promise.all([uci.load('audiowrt'),uci.load('system')]);},
	render:function(){var self=this,name=uci.get('audiowrt','main','device_name')||'AudioWRT',hostname=uci.get('system','@system[0]','hostname')||name;return E('div',{'class':'cbi-map'},[E('h2',{},_('AudioWRT System')),E('div',{'class':'cbi-section'},[E('p',{},[E('strong',{},_('Device name: ')),name]),E('p',{},[E('strong',{},_('Hostname: ')),hostname]),E('p',{},_('This page belongs to the AudioWRT distribution core. Generic OpenWrt installations using only the AudioWRT audio packages do not receive these appliance controls.')),E('button',{'class':'btn cbi-button-negative','click':function(){self.reboot();}},_('Reboot AudioWRT'))])]);},
	reboot:function(){if(!window.confirm(_('Reboot AudioWRT now?')))return;fs.exec('/sbin/reboot',[]).catch(function(err){ui.addNotification(null,E('p',{},err.message||String(err)),'error');});ui.showModal(_('Rebooting'),[E('p',{'class':'spinning'},_('AudioWRT is rebooting...'))]);},
	handleSaveApply:null,handleSave:null,handleReset:null
});
