//! An abstraction over Tauri's system tray menu structs, that implements `PartialEq` for unit testing

use connlib_shared::{callbacks::ResourceDescription, messages::ResourceId};
use serde::{Deserialize, Serialize};
use url::Url;

use super::INTERNET_RESOURCE_DESCRIPTION;

/// A menu that can either be assigned to the system tray directly or used as a submenu in another menu.
///
/// Equivalent to `tauri::SystemTrayMenu`
#[derive(Debug, Default, PartialEq, Serialize)]
pub(crate) struct Menu {
    pub(crate) entries: Vec<Entry>,
}

/// Something that can be shown in a menu, including text items, separators, and submenus
///
/// Equivalent to `tauri::SystemTrayMenuEntry`
#[derive(Debug, PartialEq, Serialize)]
pub(crate) enum Entry {
    Item(Item),
    Separator,
    Submenu { title: String, inner: Menu },
}

/// Something that shows text and may be clickable
///
/// Equivalent to `tauri::CustomMenuItem`
#[derive(Debug, PartialEq, Serialize)]
pub(crate) struct Item {
    /// An event to send to the app when the item is clicked.
    ///
    /// If `None`, then the item is disabled and greyed out.
    pub(crate) event: Option<Event>,
    /// The text displayed to the user
    pub(crate) title: String,
    /// If true, show a checkmark next to the item
    pub(crate) selected: bool,
}

/// Events that the menu can send to the app
#[derive(Debug, Deserialize, PartialEq, Serialize)]
pub(crate) enum Event {
    /// Marks this Resource as favorite
    AddFavorite(ResourceId),
    /// Opens the admin portal in the default web browser
    AdminPortal,
    /// Cancels any ongoing sign-in flow
    CancelSignIn,
    /// Copies this string to the desktop clipboard
    Copy(String),
    /// Marks this Resource as non-favorite
    RemoveFavorite(ResourceId),
    /// If a Portal connection has failed, try again immediately
    RetryPortalConnection,
    /// Starts the sign-in flow
    SignIn,
    /// Signs the user out, without quitting the app
    SignOut,
    /// Opens the About or Settings window
    ShowWindow(Window),
    /// Opens an arbitrary URL in the default web browser
    ///
    /// TODO: If we used the `ResourceId` here we could avoid any problems with
    /// serializing and deserializing user-controlled URLs.
    Url(Url),
    /// Quits the app, without signing the user out
    Quit,
    /// A resource was enabled in the UI
    EnableResource(ResourceId),
    /// A resource was disabled in the UI
    DisableResource(ResourceId),
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
pub(crate) enum Window {
    About,
    Settings,
}

fn resource_header(res: &ResourceDescription) -> Item {
    let Some(address_description) = res.address_description() else {
        return copyable(&res.pastable());
    };

    if address_description.is_empty() {
        return copyable(&res.pastable());
    }

    let Ok(url) = Url::parse(address_description) else {
        return copyable(address_description);
    };

    item(Event::Url(url), format!("<{address_description}>"))
}

impl Menu {
    pub(crate) fn add_separator(&mut self) {
        self.entries.push(Entry::Separator);
    }

    pub(crate) fn add_item(&mut self, item: Item) {
        self.entries.push(Entry::Item(item));
    }

    pub(crate) fn add_submenu<S: Into<String>>(mut self, title: S, inner: Menu) -> Self {
        self.entries.push(Entry::Submenu {
            inner,
            title: title.into(),
        });
        self
    }

    /// Builds this abstract `Menu` into a real menu that we can use in Tauri.
    ///
    /// This recurses but we never go deeper than 3 or 4 levels so it's fine.
    pub(crate) fn build(&self) -> tauri::SystemTrayMenu {
        let mut menu = tauri::SystemTrayMenu::new();
        for entry in &self.entries {
            menu = match entry {
                Entry::Item(item) => menu.add_item(item.build()),
                Entry::Separator => menu.add_native_item(tauri::SystemTrayMenuItem::Separator),
                Entry::Submenu { title, inner } => {
                    menu.add_submenu(tauri::SystemTraySubmenu::new(title, inner.build()))
                }
            };
        }
        menu
    }

    /// Appends a menu item that copies its title when clicked
    pub(crate) fn copyable(mut self, s: &str) -> Self {
        self.add_item(copyable(s));
        self
    }

    /// Appends a disabled item with no accelerator or event
    pub(crate) fn disabled<S: Into<String>>(mut self, title: S) -> Self {
        self.add_item(item(None, title).disabled());
        self
    }

    /// Appends a generic menu item
    pub(crate) fn item<E: Into<Option<Event>>, S: Into<String>>(mut self, id: E, title: S) -> Self {
        self.add_item(item(id, title));
        self
    }

    /// Appends a separator
    pub(crate) fn separator(mut self) -> Self {
        self.add_separator();
        self
    }

    fn internet_resource(self) -> Self {
        self.disabled(INTERNET_RESOURCE_DESCRIPTION)
    }

    fn resource_body(self, resource: &ResourceDescription) -> Self {
        self.separator()
            .disabled("Resource")
            .copyable(resource.name())
            .copyable(resource.pastable().as_ref())
    }

    pub(crate) fn resource_description(mut self, resource: &ResourceDescription) -> Self {
        if resource.is_internet_resource() {
            self.internet_resource()
        } else {
            self.add_item(resource_header(resource));
            self.resource_body(resource)
        }
    }
}

impl Item {
    /// Builds this abstract `Item` into a real item that we can use in Tauri.
    fn build(&self) -> tauri::CustomMenuItem {
        let mut item = tauri::CustomMenuItem::new(
            serde_json::to_string(&self.event)
                .expect("`serde_json` should always be able to serialize tray menu events"),
            &self.title,
        );

        if self.event.is_none() {
            item = item.disabled();
        }
        if self.selected {
            item = item.selected();
        }
        item
    }

    fn disabled(mut self) -> Self {
        self.event = None;
        self
    }

    pub(crate) fn selected(mut self) -> Self {
        self.selected = true;
        self
    }
}

/// Creates a menu item that copies its title when clicked
pub(crate) fn copyable(s: &str) -> Item {
    item(Event::Copy(s.to_string()), s)
}

/// Creates a generic menu item with one of our events attached
pub(crate) fn item<E: Into<Option<Event>>, S: Into<String>>(event: E, title: S) -> Item {
    Item {
        event: event.into(),
        title: title.into(),
        selected: false,
    }
}
